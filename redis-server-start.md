#redis-server启动的主流程

我们从 redis-server（src/redis.c） 启动说起，随着 main 函数浏览一下各个关键函数，了解一下 Redis 的主要程序流程。

![Redis-server-start](https://raw.github.com/redisbook/book/master/image/redis_server.png)


##initServerConfig

``initServerConfig``函数会给 server（RedisServer） 这个全局变量设置一些默认的参数，比如监听端口为 6379 ,默认的内置 db 个数为 16 等。默认值对于一个用户友好的软件非常重要，谁愿意第一次使用软件还要设置一大堆云里雾里的参数呢？所有的参数后面会详细讲述。

RedisServer 这个结构非常重要，是 Redis 服务端程序唯一的一个结构体，稍后我们会详细接收这个结构体成员的作用。

        server.commands = dictCreate(&commandTableDictType,NULL);
        populateCommandTable();                     
        server.delCommand = lookupCommandByCString("del");
        server.multiCommand = lookupCommandByCString("multi");

``PopulateCommandTable``会把命令与函数数组``readonlyCommandTable``数组结构保存到哈希表结构 server.commands，方便跨速查找。例如用户键入了``set a 1``这个命令到服务端，服务端解析协议后知道了``set`` 这个命令，就可以找到``setCommand``这个相应的处理函数，这个后面会详细描述。

另外好保存 del，multi命令的指针，方便更快速的使用。

        server.slowlog_log_slower_than = REDIS_SLOWLOG_LOG_SLOWER_THAN;
        server.slowlog_max_len = REDIS_SLOWLOG_MAX_LEN;

慢日志参数的配置，凡是超过 REDIS_SLOWLOG_LOG_SLOWER_THAN 时间的命令会被记录到慢日志里，慢日志最多能存储 REDIS_SLOWLOG_MAX_LEN 条记录。


##loadServerConfig

如果``redis-server``启动参数里有指定``redis.conf``，``LoadServerConfig``函数就会读入``redis.conf``里的参数，覆盖之前的默认值。


##initServer

 * 利用``signal``屏蔽一些信号，设置一些信号处理函数``setupSignalHandlers``。

 * 再次对 redis-server 这个数据结构做初始化。

 * createSharedObjects
    提前产生一些常用的对象，避免临时 malloc。

 * aeCreateEventLoop 创建多路服务的文件、事件事件管理器。

 * anetTcpServer 启动 6379 端口的监听。

 * anetUnixServer 启动unix socket 的监听。

 * 添加文件和时间事件。
	1. 添加一个时间事件，函数是``serverCron``。这个函数会每 100ms 执行一次，后面会详细描述这个函数的作用。
    2. 添加一个监听的文件事件，把 accept 行为注册到只读的监听文件描述符上，回凋函数是``acceptTcpHandler``。

 * slowlogInit 启动慢日志功能，发现比较慢的命令。

 * bioInit 启动后台线程来处理系统调用耗时的操作。


##aeMain(el)

进入 Redis 的主循环。

每次循环之前还会执行``beforeSleep``

然后开始循环，这个循环目前每隔 100ms 会执行一次``serverCron``函数，并仅仅盯着监听的 fd，等待外部的连接，有连接则调用``acceptTcpHandler``。


##beforeSleep
    #TODO

##serverCron

时间事件``serverCron``做很多事情。

 * 出日志展现 Redis 目前的状况。
 * 查看是否需要 rehash 来迁移 keys 到新的 bucket，这个后面会详细讲。
 * 关闭长时间不工作的 client。
 * 处理 bgsave 或者 bgrewriteaof 的子进程退出后的收尾工作。
 * 判断有 keys 的变化而需要执行 bgsave。
 * 清理过期(expire)的 key。
 * 如果自己是主库，会检测备库节点的状况，如果自己是备库，会连接主库。


##acceptTcpHandler

现在来看``redis-server``如何处理网络连接，见下一章。
