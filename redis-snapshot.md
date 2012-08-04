#持久化


Redis有全量（save/bgsave）持久化和增量（aof）的持久化命令。

##全量持久化, 快照


遍历里所有的 RedisDb ，读取每个 bucket 里链表的 key 和 value 并写入 dump.rdb 文件（rdb.c 405）。

save 命令直接调度 rdbSave 函数，这会阻塞主线程的工作，通常我们使用bgsave。

bgsave 命令调度 rdbSaveBackground 函数启动了一个子进程然后调度了rdbSave函数，子进程的退出状态由 serverCron的 backgroundSaveDoneHandler 来判断，这个在前面复制章节已经提及。

除了直接的save、bgsave命令之外，还有几个地方还调用到 rdbSaveBackground 和 rdbSave 函数。

* shutdown：Redis 关闭调度的 prepareForShutdown 会做一次持久化工作，保证重启后数据依然存在，会调用 rdbSave。

* flushallCommand：清空 Redis 数据后，如果不做立即执行一个 rdbSave，生成一个空的快照出现 crash 后，可能会载入含有老数据的快照。


    void flushallCommand(RedisClient *c) {
        touchWatchedKeysOnFlush(-1);
        server.dirty += emptyDb();      // 清空数据
        addReply(c,shared.ok);
        if (server.bgsavechildpid != -1) {
            Kill(server.bgsavechildpid,SIGKILL);
            rdbRemoveTempFile(server.bgsavechildpid);
        }
        rdbSave(server.dbfilename);    //没有数据的dump.db
        server.dirty++;
    }

* sync：当master接收到slave发来的该命令的时候，会执行 rdbSaveBackground，这个以前也有提过。


###redis.conf 相关的参数

数据发生变化：在多少秒内出现了多少次变化则触发一次 bgsave，这个可以在 redis.conf 里配置。

    for (j = 0; j < server.saveparamslen; j++) {
        struct saveparam *sp = server.saveparams+j;
        if (server.dirty >= sp->changes && now-server.lastsave > sp->seconds) {
            rdbSaveBackground(server.dbfilename);
            break;
      }
    }

