#内存分配

Redis对 malloc、free、calloc、realloc 等库函数进行了包装（zmalloc.c, zmalloc.h），把需要申请的内存的大小放在申请内存的前端，free的时候就知道这次free的内存大小。

（以下两个函数去掉编译宏，仅仅适合linux环境使用原生malloc）

    #define PREFIX_SIZE (sizeof(size_t))

    void *zmalloc(size_t size) {
        void *ptr = malloc(size+PREFIX_SIZE);
        *((size_t*)ptr) = size; 
        update_zmalloc_stat_alloc(size+PREFIX_SIZE,size);
        return (char*)ptr+PREFIX_SIZE;
    }

    void zfree(void *ptr) {
        void *realptr; 
        size_t oldsize;
        if (ptr == NULL) return; realptr = (char*)ptr-PREFIX_SIZE; 
        oldsize = *((size_t*)realptr); 
        update_zmalloc_stat_free(oldsize+PREFIX_SIZE); 
        free(realptr); 
    }

update_zmalloc_stat_alloc 会记录全局的内存申请状况 (used_memory)，与 redis.conf 里的 maxmmory 就能够控制全局的内存使用。另外还会并对内存划分的大小分组记录（zmalloc_allocations），这样你就对key-value的大小分布非常的清楚，便于接下来的迁移、合并工作。

#Sharedobjects

如果字符串是一个数字，则可以重用已经预分配的redisObject

    robj *createStringObjectFromLongLong(long long value) { 
        robj *o; 
        if (value >= 0 && value < REDIS_SHARED_INTEGERS && 
            pthread_equal(pthread_self(),server.mainthread)) { 
            incrRefCount(shared.integers[value]); //reuse share objects 
            o = shared.integers[value]; 
        } else { 
            if (value >= LONG_MIN && value <= LONG_MAX) { 
                o = createObject(REDIS_STRING, NULL); 
                o->encoding = REDIS_ENCODING_INT; 
                o->ptr = (void*)((long)value); 
            } else { 
                o = createObject(REDIS_STRING,sdsfromlonglong(value)); 
            } 
        } 
        return o; 
    } 

如果发现这个数字的大小，正好在这个范围内(0 - 1000)，那么就可以重用这个数字，而不需要动态的 malloc 一个对象了。这种使用引用技术的不变类的方法，在很多虚拟机语言里也常被使用，利用Python，java。

