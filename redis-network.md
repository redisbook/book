#网络框架简介


！[network](https://raw.github.com/redisbook/book/master/image/redis_network_arch.png)

我们知道`initServer`这个函数创建了网络监听，并``epoll_wait``在这个监听上，等待新的连接。

一旦有新的连接，则``redis-server``主线程从epoll_wait处返回，然后调用``acceptTcpHandler``函数。来处理新的连接。

##acceptTcpHandler

对于新的连接，调用`createClient`（src/networking.c）函数创建``strcut redisClient``结构。

``redisClient``伴随这个连接的生命周期所存在，记录这个连接。

下面是这个结构体的简要说明。

        typedef struct redisClient {
            int fd;                 //socket
            sds querybuf;           //读缓冲
            int argc;               //读缓冲解析后的单元个数
            robj *argv;             //读缓冲解析后的对象数组。
            int bufpos;             //写缓冲的位置
            char buf[REDIS_REPLY_CHUNK_BYTES];  //写缓冲
        }

连接建立好之后，把该连接，加入到全局的事件管理器里，当有读事件发生的时候，调用回调函数``readQueryFromClient``（src/networking.c）。


##readQueryFromClient

事件管理器发现这个连接有数据可读时，就会调用``readQueryFromClient``函数从``socket``里读取数据。

大读16k。

读取后的数据暂存于``querybuf``里，注意由于是非阻塞io，所以``querybuf``里的数据有可能是不完整的。

读取数据之后，就开始处理``querybuf``里的内容了，来到``processInputBuffer``函数。


##processInputBuffer

该函数会根据``querybuf``里的内容，进行字符串解析，存入``argv``内，然后通过``lookupCommand``确定是哪个命令。

再根据``redisServer->command``这个哈希表找到相应的函数。然后把``argv``里的参数传入相应的函数。

执行完函数之后，把执行的结果存储在``buf``里，然后再注册一个写事件函数``sendReplyToClient``。

##argc&&argv

例如一个``set a 1``的命令，解析后结果如下。

        argc = 2
        argv[0] = "set"
        argv[1] = "a"
        argv[2] = "1"


##sendReplyToClient

写事件比较简单，把``buf``里的内容通过连接统统写回去就算完成了，由于是非阻塞io，所以要判断返回值循环处理，直到``bufpos``为零。
最后再删除这个写事件。


