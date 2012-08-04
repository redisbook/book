#redis-server启动的主流程


我们从 redis-server（redis.c） 启动说起，从 main 函数开始遍历一下各个关键函数，先了解 Redis 主框架。

![Redis-server](https://raw.github.com/redisbook/book/master/image/redis_server.png)


##initServerConfig

首先``initServerConfig``函数会设置一些默认的参数，比如监听端口为 6379 ,默认的内置 db 个数为 16 等。默认值对于一个用户友好的软件非常重要，谁愿意第一次使用软件还要设置一大堆云里雾里的参数呢？所有的参数后面会详细讲述。

``PopulateCommandTable``会把命令与函数数组``readonlyCommandTable``转化成哈希表结构，例如用户键入了``set a 1``这个命令到服务端，服务端解析协议后知道了``set`` 这个命令，就可以找到``setCommand``这个相应的处理函数，这个后面会详细描述。


##loadServerConfig

如果``redis-server``启动参数里有``redis.conf``，``LoadServerConfig``就会读入``redis.conf``里的参数，覆盖默认值。


##initServer

 * 利用``signal``屏蔽一些信号，设置一些信号处理函数``setupSignalHandlers``。

 *  ``struct RedisServer`` 这个数据结构做初始化，这个结构是``redis-server``最重要的结构。

 * createSharedObjects

 * aeCreateEventLoop 创建多路服务的文件、事件事件管理器。

 * anetTcpServer 启动 6379 端口的监听。

 * anetUnixServer 启动unix socket 的监听，本文不讲解。

 * 添加文件和时间事件。
	1. 添加一个时间事件，函数是``serverCron``。这个函数会每 100ms 执行一次，后面会详细描述这个函数的作用。 
    2. 添加一个监听的文件事件，把 accept 行为注册到只读的监听文件描述符上。

 * slowlogInit 启动慢日志功能，发现比较慢的命令。

 * bioInit 启动后台线程来处理耗时的操作。


##aeMain(el)

这就是 Redis 的主循环。

每次循环之前还会执行``beforeSleep``

然后开始循环，这个循环目前每隔 100ms 会执行一次``serverCron``函数，并仅仅盯着监听的 fd，等待外部的连接。






时间事件 serverCron 会处理很多函数，例如定时打出日志展现 Redis 目前的状况，查看是否需要 rehash 来迁移 keys 到新的 bucket，这个后面会详细讲。关闭长时间不工作的 client。处理 bgsave 或者 bgrewriteaof 的子进程退出后的收尾工作。判断有 keys 的变化而需要执行 bgsave。清理过期(expire)的key。检测 slave 节点的状况，处理自己作为 slave 的连接主库的工作。
