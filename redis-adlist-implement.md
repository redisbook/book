---
layout: post
title: "Redis 链表结构实现分析"
description: ""
category: "Redis 源码分析"
tags: ["Redis", "源码分析", "C", "数据结构", "链表", "双端链表", "迭代器模式"]
---
{% include JB/setup %}

本文内容
-------------

链表是 Redis 的核心数据结构之一，它不仅大量应用在 Redis 自身内部的实现中，而且它也是 Redis 的 List 结构的底层实现之一。

本文通过分析 Redis 源码里的 ``adlist.h`` 和 ``adlist.c`` ，了解链表结构的详细实现，籍此加深对 Redis 的理解。


数据结构
---------------

Redis 的链表结构是一个典型的双端链表（[doubly linked list](http://en.wikipedia.org/wiki/Doubly_linked_list)）实现。

除了一个指向值的 ``void`` 指针外，链表中的每个节点都有两个方向指针，一个指向前驱节点，另一个指向后继节点：

{% highlight c %}
typedef struct listNode {
    struct listNode *prev;
    struct listNode *next;
    void *value;
} listNode;
{% endhighlight %}

每个双端链表都被一个 ``list`` 结构包装起来， ``list`` 结构带有两个指针，一个指向双端链表的表头节点，另一个指向双端链表的表尾节点，这个特性使得 Redis 可以很方便地执行像 [RPOPLPUSH](http://redis.readthedocs.org/en/latest/list/rpoplpush.html) 这样的命令：

{% highlight c %}
typedef struct list {
    listNode *head;
    listNode *tail;

    void *(*dup)(void *ptr);
    void (*free)(void *ptr);
    int (*match)(void *ptr, void *key);

    unsigned long len;
} list;
{% endhighlight %}

链表结构中还有三个函数指针 ``dup`` 、 ``free`` 和 ``match`` ，这些指针指向那些用于处理不同类型值的函数。

至于 ``len`` 属性，毫无疑问，就是链表节点数量计数器了。

以下是双端链表和节点的一个示意图：

![双端链表和节点示意图](https://github.com/huangz1990/huangz1990.github.com/raw/d302df795df25c425b12492ed885d544f5709bb2/_image/2012-07-19/list_and_list_node.png)


list 结构和 listNode 结构的 API
--------------------------------------

``list`` 和 ``listNode`` 都有它们自己的一簇 API ，这些 API 的实现都是典型的双端链表 API ，这里就不作详细的分析了。

从名字上就可以大概地看出它们的作用：

{% highlight c %}
list *listCreate(void);
void listRelease(list *list);

list *listAddNodeHead(list *list, void *value);
list *listAddNodeTail(list *list, void *value);
list *listInsertNode(list *list, listNode *old_node, void *value, int after);
void listDelNode(list *list, listNode *node);

list *listDup(list *orig);

listNode *listSearchKey(list *list, void *key);
listNode *listIndex(list *list, long index);

void listRotate(list *list);
{% endhighlight %}

为了方便操作列表，源码中还定义了一组宏：

{% highlight c %}
#define listLength(l) ((l)->len)
#define listFirst(l) ((l)->head)
#define listLast(l) ((l)->tail)
#define listPrevNode(n) ((n)->prev)
#define listNextNode(n) ((n)->next)
#define listNodeValue(n) ((n)->value)

#define listSetDupMethod(l,m) ((l)->dup = (m))
#define listSetFreeMethod(l,m) ((l)->free = (m))
#define listSetMatchMethod(l,m) ((l)->match = (m))

#define listGetDupMethod(l) ((l)->dup)
#define listGetFree(l) ((l)->free)
#define listGetMatchMethod(l) ((l)->match)
{% endhighlight %}


迭代器
-----------

Redis 针对 ``list`` 结构实现了一个[迭代器](http://en.wikipedia.org/wiki/Iterator)，用于对链表进行遍历。

这个迭代器的实现非常典型，它的结构定义如下：

{% highlight c %}
typedef struct listIter {
    listNode *next;
    int direction;  // 指定迭代的方向（从前到后还是从后到前)
} listIter;
{% endhighlight %}

``direction`` 决定迭代器是沿着 ``next`` 指针向后迭代，还是沿着 ``prev`` 指针向前迭代，这个值可以是 ``adlist.h`` 中的 ``AL_START_HEAD`` 常量或 ``AL_START_TAIL`` 常量：

{% highlight c %}
#define AL_START_HEAD 0
#define AL_START_TAIL 1
{% endhighlight %}

以下是迭代器所使用的 API ：

{% highlight c %}
listIter *listGetIterator(list *list, int direction);
listNode *listNext(listIter *iter);

void listReleaseIterator(listIter *iter);

void listRewind(list *list, listIter *li);
void listRewindTail(list *list, listIter *li);
{% endhighlight %}


小结
-----

和以往不同，因为双端链表和链表迭代器都非常常见，所以这篇文章没有像往常一样，对实现源码作详细的分析，而是将注意力集中到数据结构的定义，以及 API 的展示上。

如果对源码的细节感兴趣，可以到 GITHUB 上查看带注释的完整源码： [https://github.com/huangz1990/reading_redis_source](https://github.com/huangz1990/reading_redis_source) 。
