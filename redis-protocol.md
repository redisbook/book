#协议

协议解析这章先以``get a``这样的一个命令作为例子讲解以方便理解。

Redis 的协议是纯文本协议，没有任何二进制，牺牲了效率，牺牲了解析代码量，但方便了诊断，方便理解。

由于是文本协议，你可以通过``telnet``发送命令给``redis-server``。

与之不同的是通过``redis-cli``、利用``api``库发送的协议格式是更利于服务端解析的格式，对协议组装（常见的是长度放到前头，还有添加阿协议类型）。


#处理协议

Redis 的网络事件库，我们在前面的文章已经讲过，``readQueryFromClient``先从连接里中读取数据，先存储在``c->querybuf``里。

接下来函数``processInputBuffer``来解析``querybuf``，上面说过如果是``telnet``发送的裸协议数据是没有任何辅助信息，针对``telnet``的数据跳到 ``processInlineBuffer``函数，而其他则通过函数``processMultibulkBuffer``来处理。

这两个函数的作用一样，解析``querybuf``的字符串，分解成多参数到``argc``和``argv``里面，``argc``表示参数的个数，``argv``是个 Redis_object 的指针数组，每个指针指向一个``redisObject``, ``redisObject``的ptr里存储具体的内容，对于”get a“的请求转化后，``argc``就是2，``argv``就是

        (gdb) p (char\*)(\*c->argv[0])->ptr
        $28 = 0x80ea5ec "get"
        (gdb) p (char*)(*c->argv[1])->ptr
        $26 = 0x80e9fc4 "a"

协议解析后就执行命令。``processCommand``首先调用``lookupCommand``找到``get``对应的函数。

getCommand 比较简单，通过另一个全局的 server.db 这个 hash table 来查找 key，并返回 Redis object ，然后通过 addReplyBulk 函数返回结果。

##Requests格式

        参数的个数 CRLF
        $第一个参数的长度CRLF
        第一个参数CRLF
        ...
        $第N个参数的长度CRLF
        第N个参数CRLF

例如在Redis_cli里键入get a，经过协议组装后的请求为

        2\r\n$3\r\nget\r\n$1\r\na\r\n

## Reply格式


### bulk replies

bulk replies 是以$打头消息体，格式$值长度\r\n值\r\n，一般的 get 命令返回的结果就是这种格式。

        Redis>get aaa

        $3\r\nbbb\r\n

对应的的处理函数 addReplyBulk

        addReplyBulkLen(c,obj);             //$3
        addReply(c,obj);
        addReply(c,shared.crlf);


### error message

是以-ERR 打头的消息体，后面跟着出错的信息，以\r\n结尾，针对命令出错。

        Redis>d

        -ERR unknown command 'd'\r\n

处理的函数是 addReplyError

        addReplyString(c,"-ERR ",5);
        addReplyString(c,s,len);
        addReplyString(c,"\r\n",2);


### integer reply 

是以:打头，后面跟着数字和\r\n。

        Redis>incr a
        :2\r\n

处理函数是

        addReply(c,shared.colon);
        addReply(c,o);
        addReply(c,shared.crlf);

### status reply

以+打头，后面直接跟状态内容和\r\n

        Redis>ping
        +PONG\r\n

处理函数是 addReplyStatus

        addReplyString(c,"+",1);            //+
        addReplyString(c,s,len);
        addReplyString(c,"\r\n",2);



这里要注意reply经过协议加工后，都会先保存在 c->buf 里，c->bufpos 表示 buf 的长度。待到事件分离器转到写出操作（sendReplyToClient）的时候，就把 c->buf 的内容写入到 fd 里，c->sentlen 表示写出长度。当 c->sentlen = c->bufpos 才算写完。

### Multi-bulk 

复合应答，对于sinter，config get，keys，zrangebyscore，slowlog，hgetall 这类函数通常需要返回多个值，这类消息结构与请求的格式一模一样。
这类回复的一个特点，只有命令函数执行结束后，才能准确的知道 replies 的个数。

lrangeCommand 为什么不在此列？我们知道 Redis 的双链表的头部保留了一个链表长度字段，所以 lrange 命令在遍历链表之前，就能准确的知道应答的个数。

为什么要使用 c->reply 这个链表存储返回的值，c—>buf 数组不能满足需求么，bulk repies 就是使用 c->buf 的。

replies 的个数放在协议的最前面。只有链表，哈希，集合，数组遍历完毕之后我们才能知道 replies 的个数，如果使用 c->buf，遍历完毕后需要产生一个新的字符串，写入 replies 个数，再 strcpy c->buf 到新的字符串。我们不知道内容有多大，所以这里数组实在不适合存储临时回包数据。

所以 redis 在此处对回包数据进行分段，每段为一个字符串对象，存储在 c->reply 链表的上，每个字符串最大为 REDIS_REPLY_CHUNK_BYTES。

步骤如下：

* addDeferredMultiBulkLength
    往 c->reply 链表尾部添加一个空的字符串对象，从此 addReply 不再往 c->buf 里写数据了，而是走到 addReply*ToList 等函数。

* addReply*ToList

        tail = listNodeValue(listLast(c->reply));
                                   
        /* Append to this object when possible. */
        if (tail->ptr != NULL &&   
            sdslen(tail->ptr)+sdslen(o->ptr) <= REDIS_REPLY_CHUNK_BYTES)
        {                          
            c->reply_bytes -= zmalloc_size_sds(tail->ptr);
            tail = dupLastObjectIfNeeded(c->reply); 
            tail->ptr = sdscatlen(tail->ptr,o->ptr,sdslen(o->ptr));
            c->reply_bytes += zmalloc_size_sds(tail->ptr);      
        } else {                   
            incrRefCount(o);    
            listAddNodeTail(c->reply,o);
            c->reply_bytes += zmalloc_size_sds(o->ptr);  
        }

    找到链表最末尾的对象，因为回包都是字符串，所以肯定是 sds 字符串对象，判断现有长度和新增长度是否分段的上限？否，则继续写入这个对象。是，则链表尾部插入这个一个新的对象。

* setDeferredMultiBulkLength
    把 multi replies 的个数，写入 addDeferredMultiBulkLength 创建的字符串内部，然后再和链表下一个字符串内容进行结合，可以看到这里的内存拷贝最大就是 REDIS_REPLY_CHUNK_BYTES 字节。

        len->ptr = sdscatlen(len->ptr,next->ptr,sdslen(next->ptr));


