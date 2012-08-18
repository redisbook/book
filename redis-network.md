#网络框架简介


![network](https://raw.github.com/redisbook/book/master/image/redis_network_arch.png)

我们知道`initServer`这个函数创建了网络监听，并``epoll_wait``在这个监听上，等待新的连接。

一旦有新的连接，则``redis-server``主线程从``epoll_wait``处返回，然后调用``acceptTcpHandler``函数。来处理新的连接。

##acceptTcpHandler

对于新的连接，调用`createClient`（src/networking.c）函数创建``strcut redisClient``结构，``redisClient``伴随这个连接的生命周期所存在，记录这个连接的所有信息。

下面是这个结构体的简要说明，仅仅包含读写缓冲区的字段。

        typedef struct redisClient {
            int fd;                 //socket
            sds querybuf;           //读缓冲
            int argc;               //读缓冲解析后的单元个数
            robj *argv;             //读缓冲解析后的对象数组。

            list *reply;            //multi replies 写缓冲链表
            int reply_bytes         //multi replies 写缓冲链表内字符串的总长度，好像没作用

            int sentlen;            //写缓冲数组的已经写出的位置
            int bufpos;             //写缓冲数组的末尾
            char buf[REDIS_REPLY_CHUNK_BYTES];  //单回应写缓冲数组
        }

连接建立好之后，把该连接，加入到全局的事件管理器里，当有读事件发生的时候，调用回调函数``readQueryFromClient``（src/networking.c）。


##readQueryFromClient

事件管理器发现这个连接有数据可读时，就会调用``readQueryFromClient``函数从``socket``里读取数据。

读取后的数据暂存于``querybuf``里，注意由于是非阻塞io，所以``querybuf``里的数据有可能是不完整的。

读取数据之后，就开始处理``querybuf``里的内容了，来到``processInputBuffer``函数。


##processInputBuffer

该函数会根据``querybuf``里的内容，进行字符串解析，存入``argv``内，然后通过``lookupCommand``确定``argv[1]``是哪个命令。

再根据``redisServer->command``这个哈希表找到命令相应的函数。然后把``argv``里的参数传入相应的函数。

## call

这是 Redis 最核心函数。执行完相应的命令之后，还有几步工作要做。s

* 记录命令是否导致键值的变化，如果有变化则需要把变化传播到备库。

        if ((dirty > 0 || c->cmd->flags & REDIS_CMD_FORCE_REPLICATION) &&
        listLength(server.slaves))                     
        replicationFeedSlaves(server.slaves,c->db->id,c->argv,c->argc);

* 如果激活 AOF，则还会把变化写入到 AOF 文件。

        if (server.appendonly && dirty > 0)
            feedAppendOnlyFile(c->cmd,c->db->id,c->argv,c->argc);

* 如果存在监控客户连接，则把命令发送给该客户连接

        if (listLength(server.monitors))
            replicationFeedMonitors(server.monitors,c->db->id,c->argv,c->argc);

* 判断命令的执行时间是否超过慢日志的阀值，是否需要写入满日志

        slowlogPushEntryIfNeeded(c->argv,c->argc,duration);

执行完函数之后，把执行的结果存储在``buf``里，然后再注册一个写事件函数``sendReplyToClient``。


## c->argc, c->argv

例如一个``set a 1``的命令，解析后结果如下。

        argc = 2
        argv[0] = "set"
        argv[1] = "a"
        argv[2] = "1"


##sendReplyToClient

写事件比较简单，把``buf``里的内容通过连接统统写回去就算完成了，由于是非阻塞io，所以要判断返回值循环处理，直到``bufpos``为零。
最后再删除这个写事件。


好了这就是一个处理命令的全过程，简单吧，下面还会详细介绍。


