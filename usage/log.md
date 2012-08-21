# 日志

一般来说，操作系统都会提供详细的日志功能，不过在一些情况下，也可以考虑将日志保存到 Redis 当中：

- 你需要将多个机器的日志集中保存到一个日志服务器中

- 你需要借助 Redis 提供的数据结构来对日志内容进行操作，查看或者用于数据分析

有至少三种的方法在 Redis 中实现日志功能，它们的主要功能都一样，但也有各自不同的特色，以下几个小节就会分别介绍这些实现。


## API

一个日志系统应该（至少）包含以下几个基本操作：

``write(category, content)``

写分类 ``category`` 的新日志，内容为 ``content`` 。

``read(category, n)``

返回 ``category`` 分类的第 n 条日志， ``n`` 以 ``0`` 为开始。

``read_all(category)``

返回 ``category`` 分类的所有日志。

``count(category)``

返回 ``category`` 分类的日志数量。

``flush(category)``

清空所有分类为 ``category`` 的日志。


## 定长日志

定长日志的想法来自 Redis 的 [APPEND 命令文档](http://redis.readthedocs.org/en/latest/string/append.html)：它将数据保存在一个字符串中，新日志通过 ``APPEND`` 命令追加到字符串的最后，因为日志的长度是固定的，所以给定一个日志号码 ``n`` ，可以根据 ``n`` 和日志长度来算出日志在字符串中的起始索引和结尾索引，然后用 [GETRANGE](http://redis.readthedocs.org/en/latest/string/getrange.html) 命令取出日志的内容。

以下是一个保存年份的定长日志定义，它假设所有日志的长度都为 ``4`` ：

    require 'redis'

    LENGTH = 4

    $redis = Redis.new

    def write(category, content)
        raise "Content's length must equal to #{LENGTH}" unless content.length == LENGTH 
        return $redis.append(category, content)
    end

    def read(category, n)
        return $redis.getrange(category, n*LENGTH, (n+1)*LENGTH-1)
    end

    def read_all(category)
        all_log = $redis.get(category)
        total_log_length = count(category)

        arr = Array.new
        0.upto(total_log_length-1) do |i|
            arr << all_log[i*LENGTH ... (i+1)*LENGTH]
        end
        
        return arr
    end

    def count(category)
        total_log_length = $redis.strlen(category)
        if total_log_length == 0
            return 0
        else
            return total_log_length / LENGTH
        end
    end

    def flush(category)
        return $redis.del(category)
    end

测试：

    irb(main):001:0> load 'fixed_size_log.rb'
    => true
    irb(main):002:0> write('year-log', '2012')
    => 4
    irb(main):003:0> write('year-log', '2015')
    => 8
    irb(main):004:0> write('year-log', '123456789')     # 长度必须符合要求
    RuntimeError: Content's length must equal to 4
        from fixed_size_log.rb:8:in `write'
        from (irb):4
        from /usr/bin/irb:12:in `<main>'
    irb(main):005:0> read('year-log', 0)
    => "2012"
    irb(main):006:0> read('year-log', 1)
    => "2015"
    irb(main):007:0> read_all('year-log')
    => ["2012", "2015"]
    irb(main):008:0> count('year-log')
    => 2
    irb(main):009:0> flush('year-log')
    => 1
    irb(main):010:0> count('year-log')
    => 0


## 列表日志

列表日志的功能和定长日志差不多，它和定长日志的主要区别有以下两个：

1. 列表日志将日志内容保存在列表中，通过 [RPUSH](http://redis.readthedocs.org/en/latest/list/rpush.html) 命令添加日志、 [LINDEX](http://redis.readthedocs.org/en/latest/list/lindex.html) 命令和 [LRANGE](http://redis.readthedocs.org/en/latest/list/lrange.html) 命令读取日志。

2. 列表日志不对日志长度进行要求。

列表日志的定义如下：


    require 'redis'

    $redis = Redis.new

    def write(category, content)
        return $redis.rpush(category, content)
    end

    def read(category, n)
        return $redis.lindex(category, n)
    end

    def read_all(category)
        return $redis.lrange(category, 0, -1)
    end

    def count(category)
        return $redis.llen(category)
    end

    def flush(category)
        return $redis.del(category)
    end

测试：

    irb(main):001:0> load 'list_log.rb'
    => true
    irb(main):002:0> write('greet-log', 'good morning!')
    => 1
    irb(main):003:0> write('greet-log', 'hello world!')
    => 2
    irb(main):004:0> write('greet-log', 'moto moto!')
    => 3
    irb(main):005:0> read('greet-log', 2)
    => "moto moto!"
    irb(main):006:0> read_all('greet-log')
    => ["good morning!", "hello world!", "moto moto!"]
    irb(main):007:0> count('greet-log')
    => 3
    irb(main):008:0> flush('greet-log')
    => 1
    irb(main):009:0> count('greet-log')
    => 0


## 时间日志

时间日志保存在 Redis 的有序集合中，它将内容和时间信息一起保存在日志里，通过 [ZADD](http://redis.readthedocs.org/en/latest/sorted_set/zadd.html) 、 [ZRANGE](http://redis.readthedocs.org/en/latest/sorted_set/zrange.html) 、 [ZCARD](http://redis.readthedocs.org/en/latest/sorted_set/zcard.html) 等命令进行操作：

    require 'redis'

    $redis = Redis.new

    def write(category, content)
        return $redis.zadd(category, Time.now.to_f, content)
    end

    def read(category, n)
        return $redis.zrange(category, n, n, :with_scores => true)
    end

    def read_all(category)
        return $redis.zrange(category, 0, -1, :with_scores => true)
    end

    def count(category)
        return $redis.zcard(category)
    end

    def flush(category)
        return $redis.del(category)
    end

以下代码段模拟了一次服务器从链接失败到下线的过程，每个事件发生时的详细时间都被记录了下来：

    irb(main):001:0> load 'time_log.rb'
    => true
    irb(main):002:0> write('server-log', 'db connect fail')
    => true
    irb(main):003:0> write('server-log', 'db reconnect fail')
    => true
    irb(main):004:0> write('server-log', 'db server down')
    => true
    irb(main):005:0> read('server-log', 0)
    => ["db connect fail", 1344786364.5974884]
    irb(main):006:0> read_all('server-log')
    => [["db connect fail", 1344786364.5974884], ["db reconnect fail", 1344786375.6293638], ["db server down", 1344786389.518898]]
    irb(main):007:0> count('server-log')
    => 3
    irb(main):008:0> flush('server-log')
    => 1
    irb(main):009:0> count('server-log')
    => 0


## 实例：时间线

日志除了应用在系统的内部之外，还可在程序外部作为一个单独的功能来使用。

以时间日志为例子，很多网站都有自己的功能更新记录，这些记录通常有以下的形式：

    ...
    2012 年 9 月 11 日 添加评论功能
    2012 年 8 月 26 日 添加用户上传功能
    2012 年 8 月 15 日 添加 wiki 功能
    2012 年 8 月 10 日 网站上线

还有一种被称为时间线的功能，它和上面的功能记录一样，只是时间线通常用在记录用户信息而不是网站信息，比如：

    ...
    2012 年 8 月 12 日 21 时 你写了文章《Redis 源码分析（1）》
    2012 年 8 月 11 日 20 时 你关注了 @peter
    2012 年 8 月 11 日 18 时 @peter 关注了你
    2012 年 8 月 10 日 13 时 你注册了网站

以上两种功能的写入和读取操作，都可以使用前面给出的时间日志实现来处理。除此之外，我们还要添加一个新的函数，用于读出最新的 ``n`` 条信息：

    load 'time_log.rb'

    def recent(category, n)
        return $redis.zrevrange(category, 0, n-1, :with_scores => true)
    end

以下是一个时间线实例：

    irb(main):001:0> load 'timeline.rb'
    => true
    irb(main):002:0> write('user-timeline', 'register')                    # 写入
    => true
    irb(main):003:0> write('user-timeline', '@peter following you')
    => true
    irb(main):004:0> write('user-timeline', 'you following @peter')
    => true
    irb(main):005:0> write('user-timeline', 'you write new post Redis code analysis (1)')
    => true
    irb(main):006:0> write('user-timeline', '@peter comment on post Redis code analysis (1)')
    => true
    irb(main):007:0> write('user-timeline', '@tom comment on post Redis code analysis (1)')
    => true
    irb(main):008:0> recent('user-timeline', 5).each {|msg| p msg}       # 读取并打印最新 5 条时间线信息
    ["@tom comment on post Redis code analysis (1)", 1344850781.377236]
    ["@peter comment on post Redis code analysis (1)", 1344850767.113229]
    ["you write new post Redis code analysis (1)", 1344850732.5523758]
    ["you following @peter", 1344850695.8571677]
    ["@peter following you", 1344850683.2889433]
    => [["@tom comment on post Redis code analysis (1)", 1344850781.377236], ["@peter comment on post Redis code analysis (1)", 1344850767.113229], ["you write new post Redis code analysis (1)", 1344850732.5523758], ["you following @peter", 1344850695.8571677], ["@peter following you", 1344850683.2889433]]


## 多种日志实现之间的对比

在前面介绍的三种日志实现中，只有时间日志可以直接存储时间信息，其他两种日志需要通过编码/解码（parse、JSON等手段）来对时间信息进行支持。

另外一个需要注意的地方是，时间日志（也即是有序集合）里面不可以保存同样的值，同样内容的日记会互相覆盖， Redis 只会更新时间值：

    irb(main):001:0> load "time_log.rb"
    => true
    irb(main):002:0> write("log", "server fail")
    => true
    irb(main):003:0> read_all("log")
    => [["server fail", 1345568960.594956]]
    irb(main):004:0> write("log", "server fail")    # 写入内容相同的日志
    => false
    irb(main):005:0> read_all("log")
    => [["server fail", 1345568974.2670465]]        # 时间被更新

定长日志将所有内容都塞进一个字符串里面，所以定长日志最快，且最节省内存。不过 Redis 的字符串不提供截断（tirm）功能，因此对定长日志的部分删除操作没有其他两种日志来得方便。

定长日志和列表日志的功能基本相同，使用哪一个取决于日志内容的长度是否固定。
