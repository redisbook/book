#主框架


##主要流程


![Redis-server](image/reds_server.png)

我们从 redis-server 启动说起，从 main 函数开始遍历一下各个关键函数，先了解 Redis 主框架。

首先 initServerConfig 函数会设置一些默认的参数，比如监听端口为 6379 ,默认的 db 个数为 16 等。PopulateCommandTable 会把命令和函数数组转化成哈希表结构，这个后面会详细描述。如果启动参数里有 redis.conf，LoadServerConfig 还会读入redis.conf里的参数，覆盖默认值。

initServer会给 RedisServer 这个数据结构做初始化，申请各自成员的空间，有些是 list 结构，有些是 dict 结构。然后添加一个时间事件，函数是 serverCron。这个函数会每 100ms 执行一次，后面会详细描述这个函数的作用。然后是启动监听，注册一个监听的文件事件，把 accept 行为注册到只读的监听文件描述符上。然后如果有激活 aof 功能，还会打开 aof 文件。接着会判断数据目录是否存在镜像文件或者 aof 文件，如果存在，Redis会讲数据载入到内存中。然后进入主循环。

##文件事件, 时间事件


主循环主要处理刚才注册的时间事件和文件事件。如何保证时间事件每 100ms 执行一次，又能即时的处理网络交互的文件事件呢？

Redis 处理的比较巧妙。先执行 aeSearchNearestTimer 确定距离下次时间事件执行还有多少时间，假设第一次执行直到下次时间事件还有100ms，先执行文件事件，epool_wait 的超时时间就设置为 100ms，如果 10ms后，有网络交互后经过一系列的处理后消耗 20ms，该次循环结束。aeSearchNearestTimer 会再次计算距离下次时间事件的间隔为 100 - 10 - 20 = 70ms，于是 epoll_wait 的超时时间为 70ms，70ms之内如果没有处理文件事件，则执行时间事件。这样即保证了即时处理文件事件，在文件事件处理完毕后又能按时处理时间事件。

时间事件 serverCron 会处理很多函数，例如定时打出日志展现 Redis 目前的状况，查看是否需要 rehash 来迁移 keys 到新的 bucket，这个后面会详细讲。关闭长时间不工作的 client。处理 bgsave 或者 bgrewriteaof 的子进程退出后的收尾工作。判断有 keys 的变化而需要执行 bgsave。清理过期(expire)的key。检测 slave 节点的状况，处理自己作为 slave 的连接主库的工作。
