##数据结构


![Redis data structure](https://raw.github.com/Redisbook/book/master/image/Redis_db_data_structure.png)

每个 key-value 的数据都会存储在 RedisDb 这个结构里，而 RedisDb 就是一个 hash table。





###尽力节省空间

REDIS_STRING 和REDIS_ENCODING_RAW，假设这些数据都要存储在 Redis 内部了，这个时候全字符串肯定不是最优的存储方法。于是需要尝试的转换格式，比如“1”就应该转化成long或者longlong类型

    /* Try to encode a string object in order to save space */ 
    robj *tryObjectEncoding(robj *o) {   
        /* Check if we can represent this string as a long integer */ 
        if (isStringRepresentableAsLong(s,&value) == REDIS_ERR) return o;                                                                                 
        /* Ok, this object can be encoded... 
        if (server.maxmemory == 0 && value >= 0 && value < REDIS_SHARED_INTEGERS && 
            pthread_equal(pthread_self(),server.mainthread)) { 
            decrRefCount(o); 
            incrRefCount(shared.integers[value]); 
            return shared.integers[value]; 
        } else { 
            o->encoding = REDIS_ENCODING_INT; 
            sdsfree(o->ptr); 
            o->ptr = (void*) value; 
            return o; 
        } 
    }

如果处于共享区域，则自增加1，否则转化成INT类型。释放老的string类型，指向新的long或者longlong类型。


###如何存储


例如 "set a 1" 会创建3 个 argv,  如果数据保留了，则 1 都会incrRefCount,而不set，a 都会被删除掉
在前面可以看到全局的key是以sds形式存储的，dictAdd的时候会拷贝一份，所以a对应的object也可以删除掉，而1对应的object必须保存，这就是数据阿。


###伪代码

    processInputBuffer
        ProcessMultibulkBuffer
        while
        c->argv[c->argc++] = createStringObject(c->querybuf+pos,c->bulklen);
    
        call
        c->argv[2] = tryObjectEncoding(c->argv[2]);
        incrRefCount(val);
    
        resetClient
        freeClientArgv
        for
            decrRefCount(c->argv[j]);
        c->argc  = 0;

###表格？

type
encoding1
encoding2
condtion
REDIS_STRING
REDIS_ENCODING_RAW
REDIS_ENCODING_INT

REDIS_LIST
REDIS_ENCODING_ZIPLIST
REDIS_ENCODING_LINKEDLIST

REDIS_SET
REDIS_ENCODING_INTSET
REDIS_ENCODING_HT

REDIS_ZSET



REDIS_HASH
REDIS_ENCODING_HT
REDIS_ENCODING_ZIPMAP


ziplist是用来代替双链表，非常的节省内存
<zlbytes><zltail><zllen><entry><entry>....<zlend>
zlbytes是到zlend的距离
zllen entry的个数
zltail是最后一个entry的offset
zlend是个单字节的值，等于255,暗示链表的结尾。

String
List
Set
zset
Hash


###字符串

从图上我们可以看出 key 为”hello”，value 为 ”world” 的存储格式。

###列表
key 为 ”list“，value为一个字符串链表（“aaa”,”bbb”,”ccc”）的存储型式，


###zset


