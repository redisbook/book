

        struct  redisServer {

        redisDb *db;         /* 多个数据库的指针数组，db[0]表示第一个数据库，默认有16个 */
        list *clients;      /* 客户端对连接链表 这个链表常被遍历发现 idle 的连接 */
        dict *commands;         /* 命令与函数对应的哈希表， readonlyCommandTable 里的信息会写入这个哈希表 */

        /* RDB|AOF 加载信息 */

        int loading;           /* 如果是1表示在加载 RDB 或者 AOF 文件，除了 info 命令不能对外提供服务 */

        off_t loading_total_bytes;   /* 加载前会判断 RDB 或者 AOF 文件的大小，记录于此 */
        off_t loading_loaded_bytes;  /* 已经加载的字节数，通过它能了解加载的进度 */
        time_t loading_start_time;   /* 加载开始的时间点 */

        /* 常用命令的指针 */
        struct redisCommand *delCommand, *multiCommand; /* 某些命令经常被使用，那么保存一下指针，可以减少一个 commands 哈希表的查找工作 */
        
        list *slaves, *monitors;    /* slave 连接，monitor 连接的链表 */


        aeEventLoop *el;            /* 事件循环管理器 */

        int cronloops;

        time_t lastsave;            /* 最后一次做快照的时间点 */

        /* 慢日志相关 */
        list *slowlog;                      /* 慢日志链表 */
        long long slowlog_entry_id;         /* 慢日志记录的自增序列 */
        long long slowlog_log_slower_than;  /* 响应时间大于这个值的操作，会被记录到慢日志 */
        unsigned long slowlog_max_len;      /* 慢日志链表的最大长度 */




        /* 备库相关信息 */
        char *masterauth;                   /* 备库节点访问主库使用的密码 */
        char *masterhost;                /* 主库的 ip*/
        int masterport;                    /* 主库的端口*/
        int repl_ping_slave_period;        /* */
        int repl_timeout;
        redisClient *master;               /* 主库的连接 */
        int repl_syncio_timeout; /* timeout for synchronous I/O calls */
        int replstate;                 /* 备库的状态 */
        off_t repl_transfer_left;  /* bytes left reading .rdb  */
        int repl_transfer_s;    /* slave -> master SYNC socket */
        int repl_transfer_fd;   /* slave -> master SYNC temp file descriptor */
        char *repl_transfer_tmpfile; /* slave-> master SYNC temp file name */
        time_t repl_transfer_lastio; /* unix time of the latest read, for timeout */
        int repl_serve_stale_data; /* Serve stale data when link is down? */
        time_t repl_down_since; /* unix time at which link with master went down */


        }



#测试内存

redis-server --test-memory 4096


#配置文件
除了配置文件之外，还有一种隐蔽的参数配置方式

        hoterran@~/Projects/redis-2.4.16$ redis-server - <<eof
        > port 8000
        > maxmemory 20000
        > eof

老的配置文件方式，信息会泄漏，这种配置的好处就是文件不落地，没有密码是不能知道 redis-server的配置信息的。


配置文件可以嵌套
include




#rename command

redis 安全方面仅有一个 requirepass 参数，作为密码校验，更是没有权限的概念（其实连用户的概念都没有），这意味着一个用户既可以执行 get 命令，他也可以执行 slave of ，shutdown 命令，对于做运维的同学来说，这变的非常的不安全，天知道开发同学代码里有些啥玩意。

所有为了屏蔽那些危险的命令，redis 允许对命令进行重命名或者屏蔽，例如我对一个 get 重命名，不知道新名称的话你就不能执行该命令了。

当然 rename 命令本身应该最先被重命名。新的名称只有运维的同学自己知道，配置在 redis.conf 里。

常见的重命名的命令如下：


        } else if (!strcasecmp(argv[0],"rename-command") && argc == 3) {
            struct redisCommand *cmd = lookupCommand(argv[1]);
            int retval;
        
            if (!cmd) {
                err = "No such command in rename-command";
                goto loaderr;
            }   
        
            /* If the target command name is the emtpy string we just
             * remove it from the command table. */
            retval = dictDelete(server.commands, argv[1]);
            redisAssert(retval == DICT_OK);
        
            /* Otherwise we re-add the command under a different name. */
            if (sdslen(argv[2]) != 0) {
                sds copy = sdsdup(argv[2]);
           
                retval = dictAdd(server.commands, copy, cmd);
                if (retval != DICT_OK) {
                    sdsfree(copy);
                    err = "Target command name already exists"; goto loaderr;
                }   
            }  
   

原理就是把 server.command 里的命令给删除掉，如果存在新的名称，把新的名字和函数指针再次加入到 server.command 里。




##setupSignalHandlers

    sigsegvHandler




##freeMemoryIfNeeded


    去掉slave
    去掉 AOFBUF 暂用的临时内存大小，这部分空间是会扩展收缩的。

##info的解读

"loading_start_time:%ld\r\n"            加载开始时间
"loading_total_bytes:%llu\r\n"          需要加载的字节数目（RDB或者AOF文件的大小）   
"loading_loaded_bytes:%llu\r\n"         已经加载的字节数目
"loading_loaded_perc:%.2f\r\n"          已经加载的比率， 为前两者之商
"loading_eta_seconds:%ld\r\n"          需要多久秒才能加载完毕






##

_addReplyObjectToList 写到c->reply 里。

找到c->reply 最末尾的obj，往他的ptr上继续append，直到 REDIS_REPLY_CHUNK_BYTES



##

* lookupKey ，最标准全局键值哈希表查找，避免copy on write 

* lookupKeyRead，读查找

1. 先判断是否 expire
2. lookupKey
3. 会触发 stat_keyspace 的更新

* lookupKeyWrite，写查找

1. 先判断是否 expire
2. lookupKey

* lookupKeyReadOrReply 读查找，没找到就返回第三个参数

1. lookupKeyRead
2. addReply

* lookupKeyWriteOrReply 写查找，没找到就返回第三个参数

1. lookupKeyWrite
2. addReply





##

type


encoding







##解读命令数组

我们知道``redis-server``启动的时候会调用``populateCommandTable``函数（src/redis.c 830）把``readonlyCommandTable``数组转化成``server.commands``这个哈希表，``lookupCommand``就是一个简单的哈希取值过程，通过 key（get）找到相应的命令函数指针``getCommand``（t_string.c 437）。

我们来解读一下``readonlyCommandTable``这个结构体。

