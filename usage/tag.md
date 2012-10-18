# 打标签


## 普通标签

思路：用 Set 结构实现

示例：

一篇名叫 "Redis Tutorial" 的文章可以用以下命令来打上标签：

    redis 127.0.0.1:6379> SADD "Redis Tutorial" "redis" "tutorial" "nosql" "database"
    (integer) 4

列出标签：

    redis 127.0.0.1:6379> SMEMBERS "Redis Tutorial"
    1) "redis"
    2) "tutorial"
    3) "database"
    4) "nosql"


## 带分值的聚合型标签

思路：用 SortedSet 保存各个单独的标签信息，每个标签信息以标签名作为 member 值，用 1 作为 score 值。然后使用 ZUNIONSTORE 命令对多个标签进行聚合计算。

示例：

还是和前面一样，假设有一篇名为 "Redis Tutorial" 的文章。

Peter 将这篇文章标记为 "redis" 、"nosql" 和 "tutorial" ，执行以下操作：

    redis 127.0.0.1:6379> zadd peter-tag 1 "redis" 1 "nosql" 1 "tutorial"
    (integer) 3

Tom 将这篇文章标记为 "redis" 和 "database" ：

    redis 127.0.0.1:6379> ZADD tom-tag 1 "redis" 1 "database"
    (integer) 2

最后， Jack 将这篇文章标记为 "redis" 和 "tutorial" ：

    redis 127.0.0.1:6379> ZADD jack-tag 1 "redis" 1 "tutorial"
    (integer) 2

现在，执行以下 ZUNIONSTORE 命令，可以得出 "Redis Tutorial" 这篇文章的聚合标签结果：

    redis 127.0.0.1:6379> ZUNIONSTORE redis-tutorial-tag 3 peter-tag tom-tag jack-tag
    (integer) 4

聚合计算完成之后，使用 ZREVRANGE 查看结果：

    redis 127.0.0.1:6379> ZREVRANGE redis-tutorial-tag 0 -1 WITHSCORES
    1) "redis"
    2) "3"
    3) "tutorial"
    4) "2"
    5) "nosql"
    6) "1"
    7) "database"
    8) "1"

当然，在实际的程序中，不可能只有 3 个用户给一篇文章打标签，所以编写程序时，聚合操作需要分两步执行：

1. 查找所有给文章打了标签的用户的 key

2. 执行 ZUNIONSTORE
