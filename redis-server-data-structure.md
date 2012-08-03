##数据结构


![redis data structure](https://raw.github.com/redisbook/book/master/image/redis_db_data_structure.png)

每个 key-value 的数据都会存储在 redisDb 这个结构里，而 redisDb 就是一个 hash table。

###字符串

从图上我们可以看出 key 为”hello”，value 为 ”world” 的存储格式。

###列表
key 为 ”list“，value为一个字符串链表（[“aaa”,”bbb”,”ccc”]）的存储型式，


###zset


