# 消息传递


## 消息传递的分类

TODO: 介绍列表和订阅/发布两种实现方式。


### 持久化的和易失的

持久化消息保证除非被删除或者被取出，否则它们会一直保存在缓存区当中。

而易失消息在发送时，如果没有接收者等待这个消息，那么这个消息将被丢弃。

用 Redis 列表保存的信息总是持久化的，而使用 [PUBLISH](http://redis.readthedocs.org/en/latest/pub_sub/publish.html) 命令发送的信息则总是易失的。


### 阻塞与不阻塞

对于 Redis 的列表结构来说，接收信息是否阻塞取决于所使用的弹出原语： [LPOP](http://redis.readthedocs.org/en/latest/list/lpop.html) 和 [RPOP](http://redis.readthedocs.org/en/latest/list/rpop.html) 在取出消息时不阻塞，如果列表为空，它们就返回 ``nil`` 。

另一方面，如果使用 [BLPOP](http://redis.readthedocs.org/en/latest/list/blpop.html) 或者 [BRPOP](http://redis.readthedocs.org/en/latest/list/brpop.html) ，那么在列表为空时，阻塞直到有信息可弹出，或者等待超时为止。

对于发布/订阅机制来说， [SUBSCRIBE](http://redis.readthedocs.org/en/latest/pub_sub/subscribe.html) 命令和 [PSUBSCRIBE](http://redis.readthedocs.org/en/latest/pub_sub/psubscribe.html) 是否阻塞主要取决于所使用的驱动：比如 Ruby 的驱动 [redis-rb](https://github.com/redis/redis-rb) 在执行订阅时总是阻塞的，需要通过在 BLOCK 里设置 UNSUBSCRIBE 条件来退出。而 Python 的驱动 [redis-py](https://github.com/andymccurdy/redis-py) 则将所有消息保存到一个迭代器中，如果试图使用 ``next`` 从空迭代器中取出信息，进程就会被阻塞，但使用 ``redis.pubsub().listen()`` 进行订阅总是不阻塞的。

为了讨论的方便起见，我们假设订阅总是阻塞的。


### 一对一

TODO


### 一对多

TODO


### 多对多

TODO


## 实例

TODO


## 相关资料

[http://en.wikipedia.org/wiki/Message_(computer_science)](http://en.wikipedia.org/wiki/Message_\(computer_science\))
