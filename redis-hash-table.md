## B 树和哈希

key-value 数据库的 kv 查询的实现有很多种，
比如功能全面的 btree ，而 Redis 的作者选择了简单的 hash 来实现，使用 hash 就意味着无法使用范围查询等功能，但选择更好的 hash 函数可以达到更快的速度，而且代码的实现更简单。


## Redis 在哪里使用哈希

在 Redis 里哈希无处不在，

* server->db 全局的键值。
* server->command 命令与函数指针的关系。
* 哈希数据结构

哈希的实现在 src/dict.c，src/dict.h 里。


##hash源码分析

![Redis hash table ](https://raw.github.com/redisbook/book/master/image/redis_dict.png)

dict 为哈希表的主结构体，dictht 是为 rehash 而存在的中间数据结构（在客户端的hash table实现中是没有 dictht，见附录3），bucket 就是哈希算法里的桶，而 dictEntry 就为每个 key-value 结构体。

dictht->ht 指向 2 个 dictht。 存在 2 个 ht 的目的是为了在 rehash 的时候可以平滑的迁移桶里的数据，而不像client的dict要把老的哈希表里的一次性的全部数据迁移到新的哈希表，这种密集型的操作，在业务高峰期不可取。

每次的key-value查询过程就是，把要查询的键（Key），经过哈希函数运算后得到值（value）再次与 dictht->sizemask 求位与，这样就获得一个大于等于 0 小于等于 sizemask 的值，这个值决定了桶数组的索引。桶数组的元素是一个 dictEntry 的指针。而 dictEntry 包含一个 next 指针，这就形成了一个 dictEntry 的链表。

发生哈希冲突之时，解决冲突使用的是 seperate chaining(http://en.wikipedia.org/wiki/Hash_table#Separate_chaining)，把新的 dictEntry 加到链表的头部，所以插入是一个O(1)的操作，对于查询则是一个O(N)的操作，需要遍历这个 dictEntry 链表。

dictht->used 表示这个哈希表里已经插入的键值个数，也就是 dictEntry 的个数，每次 dictAdd 成功会对该值 +1，dictDel 成功会对该值 -1。 随着键值不断的添加，每个桶后面的单链表越来越长，查找、删除效率就变得越来越低。 


### 触发 rehash 的条件

当dict->used/dict->size >= dict_force_resize_ratio（默认是5）的时候，就认为链表较长了。

于是就有了expand和rehash的，创建一个新的hash table（ht\[1\]），expand ht[1]的bucket数组的长度为ht[0]上的两倍，rehash会把ht[0]上所有的key移动到ht[1]上。

随着 bucket 数量的增多，每个 dictEntry链表的长度就缩短了。而 hash 查找是 O（1） 不会因为 bucket 数组大小的改变而变化，而遍历链表从 O（N） 变为 O（N/2） 的时间复杂度。

## rehash

当桶后面的链表越来越长，访问目标键值变慢，就需要 rehash 来加快访问速度。

rehash 并不是一次性的迁移所有的 key，而是随着 dictAdd，dictFind 函数的执行过程调度_dictRehashStep 函数一次一个 bucket 下的 key 从 ht[0] 迁移到 ht[1]。dict->rehashidx 决定哪个 bucket 需要被迁移。当前 bucket 下的 key 都被迁移后，dict->rehashidx++，然后迁移下一个 bucket，直到所有的 bucket下的key被迁走。

除了 dict_add、dict_find 出发 rehash，另外在 serverCron 里也会调用 incrementallyRehash 函数，针对每个库的哈希表进行一次最大耗时 1s 的增量哈希，这样使得即使没有发生查询行为也会进行 rehash 的迁移。

        void incrementallyRehash(void) {
            int j;            

            for (j = 0; j < server.dbnum; j++) {
                if (dictIsRehashing(server.db[j].dict)) {
                    dictRehashMilliseconds(server.db[j].dict,1);                         
                    break; /* already used our millisecond for this loop... */
                }
            }
        }

dictRehashMilliseconds 一次 rehash 100 个桶。

        int dictRehashMilliseconds(dict *d, int ms) {
            long long start = timeInMilliseconds();
            int rehashes = 0;
 
            while(dictRehash(d,100)) {
                rehashes += 100;
                if (timeInMilliseconds()-start > ms) break;
            }
            return rehashes;
        }


rehash的具体过程如下，遍历 dict->rehashidx 对应的 bucket 下的 dictEntry 链表的每个key，对 key 进行 hash 函数运算后于 ht[1]->sizemask 求位与，确定 ht[1] 的新 bucket 位置，然后加入到 dictEntry 链表里，然后 ht[0].used--，ht[1].used++。当 ht[0].used=0，释放 ht[0] 的table，再赋值 ht[0] = ht[1]。

在rehash的过程中，如果有新的key加入，直接加到ht[1]。如果key的查找，会先查ht[0]再查询ht[1]。如果key的删除，在ht[0]找到则删除返回，否则继续到ht[1]里寻找。在rehash的过程中，不会再检测是否需要expand。由于ht[1]是ht[0]size的2倍，每次dictAdd的时候都会迁移一个bucket，所以不会出现后ht[1]满了，而ht[0]还有数据的状况。


###　resize 


