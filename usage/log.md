# 日志

TODO: 更详细的介绍

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

TODO: 更详细的解释

使用 ``APPEND`` 命令，将定长日志追加到字符串中。

来自： [APPEND 命令文档](http://redis.readthedocs.org/en/latest/string/append.html)

定义：

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
        i = 0
        while i < total_log_length do
            arr << all_log[i*LENGTH ... (i+1)*LENGTH]
            i += 1
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

TODO: 更详细的解释

定义：

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

将日志和时间信息放进 Redis 的有序集合中。

TODO: 更详细的描述

TODO： 更多和处理时间信息的 API ，比如 ``before(time)`` , ``after(time)`` , ``between(before, after)`` 等等。

定义：

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

测试：

    irb(main):001:0> load 'time_log.rb'
    => true
    irb(main):002:0> write('server-log', 'db connect fail')
    => true
    irb(main):003:0> write('server-log', 'db reconnect fail')
    => true
    irb(main):004:0> write('server-log', 'db server down')
    => true
    irb(main):005:0> read('server-log', 0)
    => [["db connect fail", 1344786364.5974884]]
    irb(main):006:0> read_all('server-log')
    => [["db connect fail", 1344786364.5974884], ["db reconnect fail", 1344786375.6293638], ["db server down", 1344786389.518898]]
    irb(main):007:0> count('server-log')
    => 3
    irb(main):008:0> flush('server-log')
    => 1
    irb(main):009:0> count('server-log')
    => 0


### 实例：时间线

TODO


## 多种日志之间的功能对比

时间日志可以直接存储时间信息，而其他两种日志需要通过编码/解码（parse、JSON等手段）来对时间信息进行支持。

定长日志最节省内存，不过 Redis 的字符串不提供截断（tirm）功能，因此对定长日志的部分删除操作没有其他两种日志来得方便。

列表日志和时间日志的功能类似，如果要对时间信息进行处理，就用时间日志；如果需要对日志进行弹出操作，就用列表日志。
