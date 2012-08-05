# 缓存


## 字符串缓存

使用 ``SET`` 、 ``GET`` 、 ``DEL`` 、 ``EXPIRE`` 等命令来处理缓存。


## 哈希缓存

使用 ``HSET`` 、 ``HGET`` 、 ``HMGET`` 、 ``HGETALL`` 、 ``EXPIRE`` 等命令来处理缓存。


## Most Recently Used （MRU）缓存和 Least Recently Used （LRU）缓存

这两种缓存都可以使用有序集合来实现，但是因为缺少关键字信息，所以它要求程序对整个缓存结果集进行遍历以查找某个单独的数据。

因此，这两种缓存方式只适用于保存那些非常『重』的查询结果。

这两种缓存的好处是可以控制缓存的数量。


## 三种缓存方式之间的功能对比

用哈希来缓存更节省内存，见官方网站 [memory-optimization topic](http://redis.io/topics/memory-optimization) 的 Using hashes to abstract a very memory efficient plain key-value store on top of Redis 部分。

字符串缓存可以独立控制过期时间，但哈希缓存只能缓存整个哈希表。
