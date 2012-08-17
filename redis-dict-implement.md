---
layout: post
title: "Redis 字典结构实现分析"
description: ""
category: "Redis 源码分析"
tags: ["Redis", "源码分析", "C"]
---
{% include JB/setup %}


简介
-----

字典是 Redis 的核心数据结构之一，在 Redis 中，每个数据库本身也是一个字典，而且字典也是 Redis 的 Hash 类型的底层实现。

本文通过分析 Redis 源码里的 ``dict.h`` 和 ``dict.c`` 文件，了解字典结构的详细实现，籍此加深对 Redis 的理解。

由于字典（哈希表）是一种非常常见的数据结构，而 ``dict.c`` 中使用的 [separate chaining 哈希表实现](http://en.wikipedia.org/wiki/Hash_table#Separate_chaining)可以在任何一本算法书上找到，因此，在本文中没有对字典的查找和增删等操作做过多的着墨，而是将重点放到整个字典结构的运作流程，以及哈希表的渐增式 rehash 操作上。


字典实现的数据结构
----------------------

``dict.h`` 文件里定义了字典实现的数据结构，比如 ``dict`` 、 ``dictht`` 和 ``dictEntry`` 等，它们之间的关系可以用下图来描述：

![字典的各个数据结构之间的关系](https://github.com/huangz1990/huangz1990.github.com/raw/246c78a03db01fd0624ec59d869477c9b86deb18/_image/2012-07-18/relationship.png)

其中， ``dict`` 结构的定义如下：

{% highlight c %}
typedef struct dict {
    dictType *type;     // 为哈希表中不同类型的值所使用的一族操作函数
    void *privdata;
    dictht ht[2];       // 每个字典使用两个哈希表（用于渐增式 rehash）
    int rehashidx;      // 指示 rehash 是否正在进行，如果不是则为 -1
    int iterators;      // 当前正在使用的 iterator 的数量
} dict;
{% endhighlight %}

代码中的注释基本说明相关属性的作用了，需要补充的一些是：

为了实现渐增式 rehash ，每个字典使用两个哈希表，分别为 ``ht[0]`` 和 ``ht[1]`` 。当 rehash 开始进行的时候， Redis 会逐个逐个地将 ``ht[0]`` 哈希表中的元素移动到 ``ht[1]`` 哈希表，直到 ``ht[0]`` 哈希表被清空为止。文章后面会给出 rehash 的相关细节。

另一方面， ``rehashidx`` 则是 rehash 操作的计数器，这方面的相关细节也会后面给出。

接下来是哈希表结构 ``dictht`` ，这个哈希表是一个典型的 separate chaining hash table 实现，它通过将哈希值相同的元素放到同一个链表中来解决冲突问题：

{% highlight c %}
typedef struct dictht {
    dictEntry **table;      // 节点指针数组
    unsigned long size;     // 桶的大小（最多可容纳多少节点）
    unsigned long sizemask; // mask 码，用于地址索引计算
    unsigned long used;     // 已有节点数量
} dictht;
{% endhighlight %}

最后要介绍的是链表的节点结构 ``dictEntry`` ：

{% highlight c %}
typedef struct dictEntry {
    void *key;              // 键
    union {
        void *val;
        uint64_t u64;
        int64_t s64;
    } v;                    // 值(可以有几种不同类型)
    struct dictEntry *next; // 指向下一个哈希节点(形成链表)
} dictEntry;
{% endhighlight %}

``dictEntry`` 中的 ``key`` 属性保存字典的键，而 ``v`` 属性则保存字典的值， ``next`` 保存一个指向 ``dictEntry`` 自身的指针，用于构成链表，解决哈希值的冲突问题。


创建字典
-------------

在初步了解了字典实现所使用的结构之后，现在是时候来看看相关的函数是怎样来操作这些结构的了。让我们从创建字典开始，一步步研究字典以及哈希表的运作流程。

使用字典的第一步就是创建字典，创建新字典执行这样一个调用链：

![首次创建字典时执行的调用序列](https://github.com/huangz1990/huangz1990.github.com/raw/246c78a03db01fd0624ec59d869477c9b86deb18/_image/2012-07-18/create-dict.png)

``dictCreate`` 函数创建一个新的 ``dict`` 结构，然后将它传给 ``_dictInit`` 函数：

{% highlight c %}
dict *dictCreate(dictType *type, void *privDataPtr)
{
    dict *d = zmalloc(sizeof(*d));

    _dictInit(d,type,privDataPtr);
    return d;
}
{% endhighlight %}

``_dictInit`` 函数为 ``dict`` 结构的各个属性设置默认值，并调用 ``_dictReset`` 函数为两个哈希表进行初始化设置：

{% highlight c %}
int _dictInit(dict *d, dictType *type, void *privDataPtr)
{
    _dictReset(&d->ht[0]);      // 初始化字典内的两个哈希表
    _dictReset(&d->ht[1]);

    d->type = type;             // 设置函数指针
    d->privdata = privDataPtr; 
    d->rehashidx = -1;          // -1 表示没有在进行 rehash
    d->iterators = 0;           // 0 表示没有迭代器在进行迭代

    return DICT_OK;             // 返回成功信号
}
{% endhighlight %}

``_dictReset`` 函数为字典的几个属性值赋值，但并不为这两个哈希表的链表数组分配空间：

{% highlight c %}
static void _dictReset(dictht *ht)
{
    ht->table = NULL;   // 未分配空间
    ht->size = 0;
    ht->sizemask = 0;
    ht->used = 0;
}
{% endhighlight %}


哈希表链表的创建流程
------------------------

每个 ``dict`` 结构都使用两个哈希表，分别是 ``dict->h1[0]`` 和 ``dict->ht[1]`` ，为了称呼方便，从现在开始，我们将它们分别叫做 0 号哈希表和 1 号哈希表。

从上一节的介绍可以知道，创建一个新的字典并不为哈希表的链表数组分配内存，也即是 ``dict->ht[0]->table`` 和 ``dict->ht[1]->table`` 都被设为 ``NULL`` 。

只有当首次调用 ``dictAdd`` 向字典中加入元素的时候， 0 号哈希表的链表数组才会被创建， ``dictAdd`` 执行这样一个调用序列：


![首次添加元素到字典时执行以下调用序列](https://github.com/huangz1990/huangz1990.github.com/raw/246c78a03db01fd0624ec59d869477c9b86deb18/_image/2012-07-18/add-element.png)

``dictAddRaw`` 是向字典加入元素这一动作的底层实现，为了计算新加入元素的 ``index`` 值，它会调用 ``_dictKeyIndex`` ：

{% highlight c %}
dictEntry *dictAddRaw(dict *d, void *key)
{
    // 被省略的代码... 

    // 计算 key 的 index 值
    // 如果 key 已经存在，_dictKeyIndex 返回 -1 
    if ((index = _dictKeyIndex(d, key)) == -1)
        return NULL;

    // 被省略的代码... 
}
{% endhighlight %}

``_dictKeyIndex`` 会在计算 ``index`` 值之前，先调用 ``_dictExpandIfNeeded`` ，检查两个哈希表是否有足够的空间容纳新元素：

{% highlight c %}
static int _dictKeyIndex(dict *d, const void *key)
{
    // 被省略的代码...

    /* Expand the hashtable if needed */
    if (_dictExpandIfNeeded(d) == DICT_ERR)
        return -1;

    // 被省略的代码...
}
{% endhighlight %}

进行到 ``_dictExpandIfNeeded`` 这一步，一些有趣的事情就开始发生了， ``_dictExpandIfNeeded`` 会检测到 0 号哈希表还没有分配任何空间，于是它调用 ``dictExpand`` ，传入 ``DICT_HT_INITIAL_SIZE`` 常量，作为哈希表链表数组的初始大小（在当前版本中， ``DICT_HT_INITIAL_SIZE`` 的默认值为 ``4`` ）：

{% highlight c %}
static int _dictExpandIfNeeded(dict *d)
{
    // 被省略的代码...

    /* If the hash table is empty expand it to the intial size. */
    if (d->ht[0].size == 0) return dictExpand(d, DICT_HT_INITIAL_SIZE);

    // 被省略的代码...
}
{% endhighlight %}

``dictExpand`` 会创建一个分配了链表数组的新哈希表，然后进行判断，决定是应该将新哈希表赋值给 0 号哈希表，还是 1 号哈希表：

{% highlight c %}
int dictExpand(dict *d, unsigned long size)
{
    // 创建带链表数组的新哈希表 
    dictht n; /* the new hash table */
    unsigned long realsize = _dictNextPower(size);

    /* the size is invalid if it is smaller than the number of
     * elements already inside the hash table */
    if (dictIsRehashing(d) || d->ht[0].used > size)
        return DICT_ERR;

    /* Allocate the new hash table and initialize all pointers to NULL */
    n.size = realsize;
    n.sizemask = realsize-1;
    n.table = zcalloc(realsize*sizeof(dictEntry*));
    n.used = 0;

    /* Is this the first initialization? If so it's not really a rehashing
     * we just set the first hash table so that it can accept keys. */
    if (d->ht[0].table == NULL) {
        d->ht[0] = n;       // 将新哈希表赋值给 0 号哈希表
        return DICT_OK;     // 然后返回
    }

    // 被省略的代码 ...
}
{% endhighlight %}

到了这一步， 0 号哈希表已经从无到有被创建出来了。


字典的扩展，以及 1 号哈希表的创建
--------------------------------------

在 0 号哈希表创建之后，字典就可以支持增加、删除和查找等操作了。

唯一的问题是，这个最初创建的 0 号哈希表非常小，它很快就会被添加进来的元素填满，这时候，字典的扩展（expand）机制就会被激活，它执行一系列动作，为字典分配更多空间，从而使得字典可以继续正常运作。

因为字典的的底层实现是哈希表，所以对字典的扩展，实际上就是对（字典的）哈希表做扩展。这个过程可以分为两步进行：

1) 创建一个比现有的 0 号哈希表更大的 1 号哈希表

2) 将 0 号哈希表的所有元素移动到 1 号哈希表去

``_dictExpandIfNeeded`` 函数检查字典是否需要扩展，每次往字典里添加新元素之前，这个函数都会被执行：

{% highlight c %}
static int _dictExpandIfNeeded(dict *d)
{
    // 被省略的代码...

    // 当 0 号哈希表的已用节点数大于等于它的桶数量，
    // 且以下两个条件的其中之一被满足时，执行 expand 操作：
    // 1) dict_can_resize 变量为真，正常 expand
    // 2) 已用节点数除以桶数量的比率超过变量 dict_force_resize_ratio ，强制 expand
    // (目前版本中 dict_force_resize_ratio = 5)
    if (d->ht[0].used >= d->ht[0].size &&
        (dict_can_resize ||
         d->ht[0].used/d->ht[0].size > dict_force_resize_ratio))
        {
            return dictExpand(d, ((d->ht[0].size > d->ht[0].used) ?
                                        d->ht[0].size : d->ht[0].used)*2);
        }

    // 被省略的代码...
}
{% endhighlight %}

可以看到，当代码注释中所说的两种情况的其中一种被满足的时候， ``dictExpand`` 函数就会被调用： 0 号哈希表的桶数量和节点数量两个数值之间的较大者乘以 2 ，就会被作为第二个参数传入 ``dictExpand`` 函数。

这次调用 ``dictExpand`` 函数执行的是和之前创建 0 号哈希表时不同的路径 —— 这一次，程序执行的是 else case —— 它将新哈希表赋值给 1 号哈希表，并将字典的 ``rehashidx`` 属性从 ``-1`` 改为 ``0``：

{% highlight c %}
int dictExpand(dict *d, unsigned long size)
{
    // 创建带链表数组的新哈希表 
    dictht n; /* the new hash table */
    unsigned long realsize = _dictNextPower(size);

    /* the size is invalid if it is smaller than the number of
     * elements already inside the hash table */
    if (dictIsRehashing(d) || d->ht[0].used > size)
        return DICT_ERR;

    /* Allocate the new hash table and initialize all pointers to NULL */
    n.size = realsize;
    n.sizemask = realsize-1;
    n.table = zcalloc(realsize*sizeof(dictEntry*));
    n.used = 0;

    /* Is this the first initialization? If so it's not really a rehashing
     * we just set the first hash table so that it can accept keys. */
    if (d->ht[0].table == NULL) {
        d->ht[0] = n;
        return DICT_OK;
    }

    /* Prepare a second hash table for incremental rehashing */
    // 这次执行这个动作
    d->ht[1] = n;       // 赋值新哈希表到 d->ht[1]
    d->rehashidx = 0;   // 将 rehashidx 设置为 0
    return DICT_OK;
}
{% endhighlight %}


渐进式 rehash ，以及平摊操作
--------------------------------

在前一节的最后， ``dictExpand`` 的代码中，当字典扩展完毕之后，字典会同时使用两个哈希表（ ``d->ht[0]`` 和 ``d->ht[1]`` 都不为 ``NULL`` ），并且字典 ``rehash`` 属性的值为 ``0`` 。这意味着，可以开始对 0 号哈希表进行 rehash 操作了。

Redis 对字典的 rehash 操作是通过将 0 号哈希表中的所有数据移动到 1 号哈希表来完成的，当移动完成， 0 号哈希表的数据被清空之后， 0 号哈希表的空间就会被释放，接着 Redis 会将原来的 1 号哈希表设置为新的 0 号哈希表。如果将来这个 0 号哈希表也不能满足储存需要，那么就再次执行 rehash 过程。

需要说明的是，对字典的 rehash 并不是一次性地完成的，因为 0 号哈希表中的数据可能非常多，而一次性移动大量的数据必定对系统的性能产生严重影响。

为此， Redis 采取了一种更平滑的 rehash 机制，Redis 文档里称之为渐增式 rehash （incremental rehashing）：它将 rehash 操作平摊到 ``dictAddRaw`` 、 ``dictGetRandomKey`` 、 ``dictFind`` 和 ``dictGenericDelete`` 这四个函数里面，每当上述这些函数执行的时候（或者其他函数调用它们的时候）， ``_dictRehashStep`` 函数就会被执行，它每次将 1 个元素从 0 号哈希表移动到 1 号哈希表：

![调用_dictRehashStep的那些函数](https://github.com/huangz1990/huangz1990.github.com/raw/master/_image/2012-07-18/incremental-rehashing-functions.png)

作为展示渐增式 rehash 的一个例子，以下是 ``dictFind`` 函数的定义：

{% highlight c %}
dictEntry *dictFind(dict *d, const void *key)
{
    // 被省略的代码...

    // 检查字典(的哈希表)能否执行 rehash 操作
    // 如果可以的话，执行平摊 rehash 操作
    if (dictIsRehashing(d)) _dictRehashStep(d);

    // 被省略的代码...
}
{% endhighlight %}

其中 ``dictIsRehashing`` 是一个宏，它检查字典的 ``rehashidx`` 属性是否不为 ``-1`` ：

{% highlight c %}
#define dictIsRehashing(ht) ((ht)->rehashidx != -1)
{% endhighlight %}

如果条件成立成立的话， ``_dictRehashStep`` 就会被执行，将一个元素从 0 号哈希表转移到 1 号哈希表：

{% highlight c %}
static void _dictRehashStep(dict *d) {
    if (d->iterators == 0) dictRehash(d,1);
}
{% endhighlight %}

``_dictRehashStep`` 定义中的 ``iterators == 0`` 检查表示，当有迭代器在处理字典的时候，不能进行 rehash ，因为迭代器可能会修改字典中的元素，从而造成 rehash 错误。

就这样，如同愚公移山一般， 0 号哈希表的元素被逐个逐个地移动到 1 号哈希表，最终整个 0 号哈希表被清空，当 ``_dictRehashStep`` 再调用 ``dictRehash`` 时，被清空的 0 号哈希表就会被删除，然后原来的 1 号哈希表成为新的 0 号哈希表。

当有需要再次进行 rehash 的时候，这个循环就会再次开始。

以下是 ``dictRehash`` 函数的完整实现，它清晰地说明了如何轮换 0 号哈希表和 1 号哈希表，以及，如何将 0 号哈希表的元素 rehash 到 1 号哈希表：

{% highlight c %}
/* Performs N steps of incremental rehashing. Returns 1 if there are still
 * keys to move from the old to the new hash table, otherwise 0 is returned.
 * Note that a rehashing step consists in moving a bucket (that may have more
 * thank one key as we use chaining) from the old to the new hash table. */
int dictRehash(dict *d, int n) {
    if (!dictIsRehashing(d)) return 0;

    while(n--) {
        dictEntry *de, *nextde;

        // 如果 0 号哈希表为空，使用 1 号哈希表代替它
        /* Check if we already rehashed the whole table... */
        if (d->ht[0].used == 0) {
            zfree(d->ht[0].table);
            d->ht[0] = d->ht[1];
            _dictReset(&d->ht[1]);
            d->rehashidx = -1;
            return 0;
        }

        // 进行 rehash 
        /* Note that rehashidx can't overflow as we are sure there are more
         * elements because ht[0].used != 0 */
        assert(d->ht[0].size > (unsigned)d->rehashidx);
        while(d->ht[0].table[d->rehashidx] == NULL) d->rehashidx++;
        de = d->ht[0].table[d->rehashidx];
        /* Move all the keys in this bucket from the old to the new hash HT */
        while(de) {
            unsigned int h;

            nextde = de->next;
            /* Get the index in the new hash table */
            h = dictHashKey(d, de->key) & d->ht[1].sizemask;
            de->next = d->ht[1].table[h];
            d->ht[1].table[h] = de;
            d->ht[0].used--;
            d->ht[1].used++;
            de = nextde;
        }
        d->ht[0].table[d->rehashidx] = NULL;
        d->rehashidx++;
    }
    return 1;
}
{% endhighlight %}

另外，还有一个确保 rehash 得以最终完成的重要条件，那就是 —— 当 ``rehashidx`` 不等于 ``-1`` ，也即是 ``dictIsRehashing`` 为真时，所有新添加的元素都会直接被加到 1 号数据库，这样 0 号哈希表的大小就会只减不增，最终 rehash 总会有完成的一刻（假如新加入的元素还继续被放进 0 号哈希表，那么尽管平摊 rehash 一直在努力地进行，但说不定 rehash 还是永远也完成不了）： 

{% highlight c %}
dictEntry *dictAddRaw(dict *d, void *key)
{
    // 被省略的代码...

    // 如果字典正在进行 rehash ，那么将新元素添加到 1 号哈希表，
    // 否则，使用 0 号哈希表
    ht = dictIsRehashing(d) ? &d->ht[1] : &d->ht[0];

    // 被省略的代码...
}
{% endhighlight %}

另外，除了 ``_dictRehashStep`` 以及 ``dictAddRaw`` 的特殊处理之外，Redis 还会在每次事件中断器运行的时候，执行一个为时一毫秒的 ``rehash`` 操作，在文件 ``redis.c`` 中的 ``serverCron`` 函数中记录了这一点。


哈希表的大小
-------------------

在介绍完哈希表的使用流程和 rehash 机制之后，最后一个需要探索的地方就是哈希表的大小了。

我们知道哈希表最初的大小是由 ``DICT_HT_INITIAL_SIZE`` 常量决定的，而当 rehash 开始之后，根据给定的条件，哈希表的大小就会发生变动：

{% highlight c %}
static int _dictExpandIfNeeded(dict *d)
{
    // 被省略的代码...

    if (d->ht[0].used >= d->ht[0].size &&
        (dict_can_resize ||
         d->ht[0].used/d->ht[0].size > dict_force_resize_ratio))
    {
        return dictExpand(d, ((d->ht[0].size > d->ht[0].used) ?
        d->ht[0].size : d->ht[0].used)*2);
    }

    // 被省略的代码...
}
{% endhighlight %}

可以看到， ``d->ht[0].size`` 和 ``d->ht[0].used`` 两个数之间的较大者乘以 ``2`` ，会作为 ``size`` 参数的值被传入 ``dictExpand`` 函数。

但是，尽管如此，这个数值仍然还不是哈希表的最终大小，因为在 ``dictExpand`` 里面，真正的哈希表大小需要 ``_dictNextPower`` 函数根据传入的 ``size`` 参数计算之后才能得出：

{% highlight c %}
int dictExpand(dict *d, unsigned long size)
{
    // 被省略的代码...

    // 计算哈希表的(真正)大小
    unsigned long realsize = _dictNextPower(size);

    // 被省略的代码...
}
{% endhighlight %}

``_dictNextPower`` 不断计算 2 的乘幂，直到遇到大于等于 ``size`` 参数的乘幂，就返回这个乘幂作为哈希表的大小：

{% highlight c %}
static unsigned long _dictNextPower(unsigned long size)
{
    unsigned long i = DICT_HT_INITIAL_SIZE;

    if (size >= LONG_MAX) return LONG_MAX;
    while(1) {
        if (i >= size)
            return i;
        i *= 2;
    }
}
{% endhighlight %}

虽然桶的元素个数 ``d->ht[0].size`` 刚开始是固定的( ``DICT_HT_INITIAL_SIZE`` )，但是，因为我们没有办法预知 ``d->ht[0].used`` 的值，所以我们没有办法准确预估新哈希表的大小，不过，我们可以确定以下两个关于哈希表大小的性质：

1) 哈希表的大小总是 2 的乘幂（也即是 2^N，此处 N 未知）

2) 1 号哈希表的大小总比 0 号哈希表大


小结
--------

以上就是 Redis 字典结构的实现分析了，因为边幅所限，这里展示的函数多数都只贴出了主要部分的代码，如果对所有代码的细节感兴趣，可以到我的 GITHUB 上去找带有完整注释的代码： [https://github.com/huangz1990/reading_redis_source](https://github.com/huangz1990/reading_redis_source)
