# 如何使用``dict``

``dict.c``是个写的非常好的哈希表操作的库，值得学习，值得复用。下面讲讲要如何使用这个库。

首先需要注意这里说的``dict.c`` 是客户端 deps/dict.c，而不是服务端的 src/dict.c，两者有一些区别：

* 服务端的 rehash 是增量形式完成的，所以有 ht[0]，ht[1] 两个桶指针用于切换。而客户端的 rehash 是一次性的行为，所以 dictht 这个结构，在客户端``dict.c``就没有，这样代码就更加简单了，另外 rehash 相关的函数，在客户端里也不提供。
* 对于服务端，存在空间浪费的问题，所以引入了 dictResize 函数来对内存空间进行清空，这点在客户端里也没有提供。


先来解读一下``dictType``这个结构各个字段的作用，这非常的重要。


## dictType 解释

	typedef struct dictType {
		unsigned int (*hashFunction)(const void *key);
		void *(*keyDup)(void *privdata, const void *key);
		void *(*valDup)(void *privdata, const void *obj);
		int (*keyCompare)(void *privdata, const void *key1, const void *key2);
		void (*keyDestructor)(void *privdata, void *key);
		void (*valDestructor)(void *privdata, void *obj);
	} dictType;

以上六个回调函数是在哈希表创建之时，由使用者存入 dict 结构内，第一个``hashFunction``是必须的，另外的回调如果存在会在适当的时候被调用。


### hashFunction

当进行哈希转换之时，会调用``hashFunction``，把用户的 key 转化成一个整型数字，使用者应该根据自己的 Key 是什么类型给出响应的哈希函数。

Redis 里的 Key 为一个 sds 的字符串，所以他默认选择的 dictGenHashFunction，Redis 服务端哈希另外还提供了一下对整型（dictIntHashFunction）和对大小写敏感（dictGenCaseHashFunction）的字符串哈希函数。


### keyCompare

在进行进行键值查找之时，会调用 keyCompare 来判断两个键是否相等。

Redis 里的 Key 为一个 sds 的字符串，只要比较一下字符串是否相等（dictSdsKeyCompare）。

    #define dictCompareHashKeys(d, key1, key2) \                                        
        (((d)->type->keyCompare) ? \
            (d)->type->keyCompare((d)->privdata, key1, key2) : \
            (key1) == (key2))


### keyDup & valDup

如果没有设置 Dup 函数，那么存入键值对应的 dictEntry 里的仅仅是键值指针，如果在此之后修改了键值，也会影响到哈希表里值。

如果设置了 Dup 函数，则在 dictAdd 之时，会额外的调用 Dup 函数，对键值进行拷贝工作，那么插入之后键值就可以 free 掉了，
Redis 并没有设置使用这两个回调函数，也不推荐使用。

如果你的键值是栈上空间，那么在开始的 dictType 一定要设置 Dup 函数，一般我们也不推荐使用栈空间。

    #define dictSetHashKey(d, entry, _key_) do { \
        if ((d)->type->keyDup) \
            entry->key = (d)->type->keyDup((d)->privdata, _key_); \                                                               
        else \
            entry->key = (_key_); \
    } while(0)


### keyDestructor, valDestructor 

当调用 dictDelete 函数时，如果使用者额外的设置了 Destructor 函数，则删除之于还会调用这个函数进行键值的内存释放。

对于全局的哈希键值表，键为 sds，值为 RedisObject，所以会调用 dictSdsDestructor 和 dictRedisObjectDestructor，自动的释放键值占用的空间。

    #define dictFreeEntryVal(d, entry) \
        if ((d)->type->valDestructor) \
            (d)->type->valDestructor((d)->privdata, (entry)->val)

    #define dictFreeEntryKey(d, entry) \
        if ((d)->type->keyDestructor) \
            (d)->type->keyDestructor((d)->privdata, (entry)->key)


## 几个 api 的使用说明

	dict *dictCreate(dictType *type, void *privDataPtr); 

创建一个 dict 结构体，使用者需要先定义好 dictType，然后存入, privDataPtr 很少使用。

	int dictAdd(dict *d, void *key, void *val);

往哈希表里添加一对键值，键值是拷贝还是仅仅是指针赋值，取决于 Dup 回调函数是否设置。

	int dictDelete(dict *d, const void *key);

从哈希表里删除一对键值，如果 dictType 里设置 Destructor 函数，那么会自动调度这两个函数来释放内存，另外有个 dictDeleteNoFree 函数 无论是否设置了 Destructor 函数都不会调用。

	dictEntry * dictFind(dict *d, const void *key);

在哈希表里找到指定的键对应的 dictEntry，要拿到键还需要调用宏 dictGetEntryKey，拿到值还要调用宏 dictGetEntryVal。

	int dictReplace(dict *d, void *key, void *val);

对哈希表里的键值进行更换，如果键已存在返回 1，不存在返回 0。

	int dictExpand(dict *d, unsigned long size);

对哈希表进行扩展，size 就是扩展后桶的大小，这里要注意一下，对于服务端的这个函数，仅仅是吧 rehashidx 设置为 0，表明从 0 号桶开始增量的 rehash行为，而在客户端里，则是在函数内部一次性的弄完整个 rehash。

	void dictRelease(dict *d); 

释放整个哈希表，自然的会释放内部所有的键值。


## 几个使用的例子

我们举几个使用 dict 的例子，一下是几个步骤：

* 确定键值类型。
* 确定 Hash，Compare，Dup，Destructor 函数，其中 Hash 和 Compare 是必须的。


### 键值皆为整数的例子：

键值类型：

    typedef struct Key_t 
    {
        int k;
    } Key_t;

    typedef struct Val_t
    {
        int v;   
    } Val_t;

由于是整型，hash 函数就设置为值本身，比较函数就设置为整数的比较：

    unsigned int testHashFunction(const void *key) 
    {
        Key_t *k1 = (Key_t*)key;
        return k1->k;
    };

    unsigned int testHashFunction(const void *key) 
    {
        Key_t *k1 = (Key_t*)key;
        return k1->k;
    };

不设置 Dup 函数，Destructor 函数就是简单的 free：

    void testHashKeyDestructor(void *privdata, void *key)
    {
        free(key);
    };

    void testHashValDestructor(void *privdata, void *val)
    {
        free(val);
    };

于是我们的 dictType 就是如此：

    dictType testDictType  = {
        testHashFunction,               /* hash */
        NULL,
        NULL,
        testHashKeyCompare,             /* key compare */
        testHashKeyDestructor,          /* key destructor */
        testHashValDestructor           /* value destructor */    
    };

好吧，看下面主函数吧，简单的插入和查询：

    int main(int argc, char *argv[]) 
    {
        int ret;
        dict *d = dictCreate(&testDictType, NULL);
        assert(d);
        Key_t *k = (Key_t*)malloc(sizeof(*k)); 
        k->k = 1;
        Val_t *v = (Val_t*)malloc(sizeof(*v)); 
        v->v = 2;
        
        ret = dictAdd(d, k, v);
        assert(ret == DICT_OK);

        Val_t *v2 = dictFetchValue(d, k);

        assert(v2->v == v->v);

        printf("%d-%d-%d\n", ret, v->v, v2->v);
        return 0;
    }


### 值为字符串的例子：

键与上个例子相同，值为字符串：

    typedef struct Key_t 
    {
        int k;
    } Key_t;
     
    typedef struct Val_t
    {
        char *v;   
    } Val_t;

要注意的是这类值的 Destructor 需要特别小心，需要额外处理字段 v 的内存释放：

    void testHashValDestructor(void *privdata, void *val)
    {
        Val_t *v1 = (Val_t*) val;
        free(v1->v);
        v1->v = NULL;
        free(v1);
    };

来看看主函数：

    int main(int argc, char *argv[]) 
    {                                                              
        int ret;
        dict *d = dictCreate(&testDictType, NULL);
        assert(d);
        Key_t *k = (Key_t*)malloc(sizeof(*k)); 
        k->k = 1;
     
        Val_t *v = (Val_t*)malloc(sizeof(*v)); 
        v->v = malloc(100);
        snprintf(v->v, 100, "%s", "abcdefg");
        
        ret = dictAdd(d, k, v);
        assert(ret == DICT_OK);
     
        Val_t *v2 = dictFetchValue(d, k);
     
        assert(0 == strcmp(v2->v, v->v));
     
        printf("%d-%s-%s\n", ret, v->v, v2->v);
     
        dictRelease(d);
     
        return 0;
    }


### 键为复合结构的例子：

假设键值是一个复合结构，例如 ip 四元表：

    typedef struct Key_t 
    {
        uint32_t laddr, raddr;
        uint16_t lport, rport;
    } Key_t;

    typedef struct Val_t
    {
        char *v; 
    } Val_t;

那么我们就要为此设置特殊的哈希函数：

    static unsigned long
    hash_fun(uint32_t laddr, uint32_t raddr, uint16_t lport, uint16_t rport) 
    {
        unsigned long ret;
        
        ret = laddr ^ raddr;
        ret ^= (lport << 16) | rport;
     
        return ret;
    }

    unsigned int testHashFunction(const void *key) 
    {
        Key_t *k1 = (Key_t*)key;
        return  hash_fun(k1->laddr, k1->raddr, k1->lport, k1->rport);
    };


来看主函数：

    int main(int argc, char *argv[]) 
    {
        int ret;
        dict *d = dictCreate(&testDictType, NULL);
        assert(d);
        Key_t *k = (Key_t*)malloc(sizeof(*k)); 
        k->laddr = 112;
        k->raddr = 112;
        k->lport = 1123;
        k->rport = 3306;

        Val_t *v = (Val_t*)malloc(sizeof(*v)); 
        v->v = malloc(100);
        snprintf(v->v, 100, "%s", "abcdefg");
        
        ret = dictAdd(d, k, v);
        assert(ret == DICT_OK);

        Val_t *v2 = dictFetchValue(d, k);

        assert(0 == strcmp(v2->v, v->v));

        printf("%d-%s-%s\n", ret, v->v, v2->v);

        return 1;
    };


好了就是 dict.c 的使用过程。
