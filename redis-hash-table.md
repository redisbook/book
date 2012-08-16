##btree and hash


key-value 数据库的 kv 查询的实现有很多种，
比如功能全面的 btree ，而 Redis 的作者选择了简单的 hash 来实现，使用 hash 就意味着无法使用范围查询等功能，但选择更好的 hash 函数可以达到更快的速度，而且代码的实现更简单。

##Redis哪里用hash


在Redis里 hash 无处不在，全局的 key-value 查询，内部的 hash 数据结构，命令与函数指针的关系都是使用 hash。hash的实现在src/dict.c、src/dict.h 里。

常见的命令（例如get，set等）会调用的函数指针，这个数据结构也是以hash table的形式存储的。
每次客户端输入”set aa bb”等数据的时候，解析得到字符串”set”后，会根据“set”作为一个key，查找到value，一个函数指针（setCommand），然后再把“aa”、“bb“作为参数传给这个函数。这个hash table存储在redisServer->command里，每次redis-server启动的时候会对``readonlyCommandTable`` 这个数组进行加工（populateCommandTable）转化成 redisServer->command 这个 hash table 方便查询，而非遍历``readonlyCommandTable``查找要执行的函数。 

##hash源码分析


![Redis hash table ](https://raw.github.com/redisbook/book/master/image/redis_dict.png)

dict 为 hash table 的主结构体，dictht 是为 rehash 而存在的中间数据结构（在客户端的hash table实现中是没有 dictht，见附录3），bucket 就是 hash 算法里的桶，而 dictEntry 就为每个 key-value 结构体。 

dictht ht 指向 2 个 dictht。 存在2个ht的目的是为了在rehash的时候可以平滑的迁移bucket里的数据，而不像client的dict要把老的hash table 里的一次性的全部数据迁移到新的 hash table，这在造成一个密集型的操作，在业务高峰期不可取。

每次的key-value查询过程就是，把要查询的key，经过hash函数执行后的值与 dictht->sizemask 求位与，这样就获得一个大于等于 0 小于等于 sizemask 的值，这就定位到了 bucket 数组的位置。bucket 数组的元素是一个 dictEntry 的指针。而 dictEntry 包含一个 next 指针。

发生 hash conflict 的时候，解决 hash 冲突使用的是 seperate chaining(http://en.wikipedia.org/wiki/Hash_table#Separate_chaining) ，直接以链表的形式加到链表的头部，所以查询则是一个O(N)的操作，需要遍历这个dictEntry链表，插入在链表头部时，时间复杂度仅仅为O(1)。

dictht->used表示这个hash table里已经插入的key的个数，也就是dictEntry的个数，每次dictAdd成功会+1，dictDel成功会-1。 随着key不断的添加，如果保持bucket数组大小不变，每个bucket元素的的单链表越来越长，查找、删除效率越来越低。 


当dict->used/dict->size >= dict_force_resize_ratio（默认是5）的时候，就认为链表较长了。

于是就有了expand和rehash的，创建一个新的hash table（ht\[1\]），expand ht[1]的bucket数组的长度为ht[0]上的两倍，rehash会把ht[0]上所有的key移动到ht[1]上。

随着 bucket 数量的增多，每个 dictEntry链表的长度就缩短了。而 hash 查找是 O（1） 不会因为 bucket 数组大小的改变而变化，而遍历链表从 O（N） 变为 O（N/2） 的时间复杂度。

##rehash


rehash 并不是一次性的迁移所有的 key，而是随着 dictAdd，dictFind 函数的执行过程调度_dictRehashStep 函数一次一个 bucket 下的 key 从 ht[0] 迁移到 ht[1]。dict->rehashidx 决定哪个 bucket 需要被迁移。当前 bucket 下的 key 都被迁移后，dict->rehashidx++，然后迁移下一个 bucket，直到所有的 bucket下的key被迁走。

除了 dict_add、dict_find 出发 rehash，另外 Redis 运行过程中会调用 dictRehashMilliseconds 函数，一次 rehash 100个 bucket，直到消耗了1秒才结束 rehash，这样使得即使没有发生查询行为也会进行 rehash 的迁移。

rehash的具体过程如下，遍历 dict->rehashidx 对应的 bucket 下的 dictEntry 链表的每个key，对 key 进行 hash 函数运算后于 ht[1]->sizemask 求位与，确定 ht[1] 的新 bucket 位置，然后加入到 dictEntry 链表里，然后 ht[0].used--，ht[1].used++。当 ht[0].used=0，释放 ht[0] 的table，再赋值 ht[0] = ht[1]。

在rehash的过程中，如果有新的key加入，直接加到ht[1]。如果key的查找，会先查ht[0]再查询ht[1]。如果key的删除，在ht[0]找到则删除返回，否则继续到ht[1]里寻找。在rehash的过程中，不会再检测是否需要expand。由于ht[1]是ht[0]size的2倍，每次dictAdd的时候都会迁移一个bucket，所以不会出现后ht[1]满了，而ht[0]还有数据的状况。

