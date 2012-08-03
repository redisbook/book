#协议

下面的协议是以一个 ”get a“ 这样的一个命令作为例子讲解，方便理解。

Redis的协议是纯ascii协议，没有任何二进制东西，牺牲了效率，牺牲了解析代码量，但方便了诊断，方便理解。

你可以通过 telnet 或者 Redis_cli、利用 lib 库发送请求给 Redis server。

前者的是一种裸协议的请求发送到服务端，而后两者会对键入的请求进行协议组装帮助更好的解析（常见的是长度放到前头，还有添加阿协议类型）。


下面这个图涵盖了接收request，处理请求，调用函数，发送reply的过程。

![protocol](http://dongshenghall.xraypoint.com/?p=721)


#网络库任何处理协议


Redis 的网络事件库，我们在前面的文章已经讲过，readQueryFromClient 先从 fd 中读取数据，先存储在 c->querybuf 里(networking.c 823)。

接下来函数 processInputBuffer 来解析 querybuf，上面说过如果是 telnet 发送的裸协议数据是没有\*打头的表示参数个数的辅助信息，针对telnet的数据跳到processInlineBuffer函数，而其他则通过函数processMultibulkBuffer。

这两个函数的作用一样，解析c->querybuf的字符串，分解成多参数到c->argc和c->argv里面，argc表示参数的个数，argv是个Redis_object的指针数组，每个指针指向一个Redis_object, object的ptr里存储具体的内容，对于”get a“的请求转化后，argc就是2，argv就是

    (gdb) p (char\*)(\*c->argv[0])->ptr
    $28 = 0x80ea5ec "get"
    (gdb) p (char*)(*c->argv[1])->ptr
    $26 = 0x80e9fc4 "a"

协议解析后就执行命令。processCommand首先调用lookupCommand找到get对应的函数。在Redis server 启动的时候会调用populateCommandTable函数（Redis.c 830）把readonlyCommandTable数组转化成一个hash table（server.commands），lookupCommand就是一个简单的hash取值过程，通过key（get）找到相应的命令函数指针getCommand（ t_string.c 437）。
getCommand比较简单，通过另一个全局的server.db这个hash table来查找key，并返回Redis object，然后通过addReplyBulk函数返回结果。

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
bulk replies是以$打头消息体，格式$值长度\r\n值\r\n，一般的get命令返回的结果就是这种个格式。

    Redis>get aaa
    $3\r\nbbb\r\n

对应的的处理函数addReplyBulk

    addReplyBulkLen(c,obj);
    addReply(c,obj);
    addReply(c,shared.crlf);

### error messag
是以-ERR 打头的消息体，后面跟着出错的信息，以\r\n结尾，针对命令出错。

    Redis>d
    -ERR unknown command 'd'\r\n

处理的函数是addReplyError

    addReplyString(c,"-ERR ",5);
    addReplyString(c,s,len);
    addReplyString(c,"\r\n",2);

###integer reply 
是以:打头，后面跟着数字和\r\n。

    Redis>incr a
    :2\r\n

处理函数是

    addReply(c,shared.colon);
    addReply(c,o);
    addReply(c,shared.crlf);

###status reply
以+打头，后面直接跟状态内容和\r\n

    Redis>ping
    +PONG\r\n

这里要注意reply经过协议加工后，都会先保存在 c->buf 里，c->bufpos 表示 buf 的长度。待到事件分离器转到写出操作（sendReplyToClient）的时候，就把 c->buf 的内容写入到 fd 里，c->sentlen 表示写出长度。当 c->sentlen = c->bufpos 才算写完。

###Multi-bulk 
replies，lrange、hgetall 这类函数通常需要返回多个值，消息结构与请求的格式一模一样。相关的函数是 setDeferredMultiBulkLength。临时数据存储在链表 c->reply 里，处理方式同其他的协议格式。


