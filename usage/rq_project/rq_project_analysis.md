# RQ 项目分析

RQ(http://python-rq.org/) 是使用 Python 编写， Redis 作为后端的一个消息队列库。


## 用例

来自官网：

    # job
    import requests

    def count_words_at_url(url):
        resp = requests.get(url)
            return len(resp.text.split())

    # queue
    from rq import Queue, use_connection
    use_connection()
    q = Queue()

    # work
    from my_module import count_words_at_url
    result = q.enqueue(count_words_at_url, 'http://nvie.com')


## 数据结构


### 创建 Job 实例

每个传入队列的任务都用一个 ``Job`` 类实例来表示。

``Job`` 类保存了任务的 ``id`` 、所属队列、函数名称、函数的参数、执行结果、执行统计信息等等。

``Job`` 实例的所有信息都保存在一个 Redis 哈希表中，键名格式为 ``rq:job:<uid>`` ， ``uid`` 一般使用 ``uuid.uuid4`` 函数来生成，也可以显式地指定。

以下是一个 ``Job.id`` 例子： ``rq:job:55528e58-9cac-4e05-b444-8eded32e76a1`` 。


### 执行 Job 任务

当需要执行任务时， ``Job.fetch`` 类方法会根据 ``id`` 值，将保存在 Redis 哈希表中的数据都取回来，并返回一个保存了这些数据的 ``Job`` 实例。

``Job`` 实例的 ``func_name`` 属性保存了执行任务所需的函数名，其实说『函数名』并不太正确，因为这个 ``func_name`` 属性既可以指向一个方法，也可以指向一个函数。

根据 ``func_name`` 属性， ``Job`` 实例可以通过 ``func`` 方法找到执行任务所需的函数（或方法）。

``Job`` 实例通过调用 ``perform`` 方法，将给定参数传给给定函数，从而执行任务。


### Queue 实例

``Queue`` 类负责保存和处理任务，它使用一个 Redis 列表保存队列中所有任务的 ``id`` 值。

每个 ``Queue`` 实例都使用 ``key`` 属性的值作为列表的键，键名格式为 ``rq:queue:<name>`` ， ``name`` 属性可以显式地指定，也可以使用默认值 ``'default'`` 。

``Queue`` 以先进先出（[FIFO](http://en.wikipedia.org/wiki/FIFO)）的方式处理任务：
它使用 ``rpush`` 命令将任务 ``id`` 放进 Redis 列表；
而 ``lpop`` 和 ``blpop`` 命令则负责将任务 ``id`` 从列表中取出。


### Worker 实例

``Worker`` 负责执行任务，它可以接受一个 ``Queue`` 类实例，或者一个包含 ``Queue`` 类实例的 Python 列表作为 ``queues`` 参数。

``Worker`` 每次从队列中弹出一个 ``Job`` 实例，并派生出一个子进程来执行任务，父进程会一直等待到任务结束，或者任务执行超时。

如果任务执行成功，并且执行任务的函数的返回值不为 ``None`` ，那么将这个返回值设置给 ``Job.result`` 属性。

如果任务执行失败，那么将任务添加到 ``FailedQueue`` 队列中，等待将来重试。

整个 ``Worker`` 执行过程可以用下图简单表示：

![Worker执行流程图](https://raw.github.com/redisbook/book/4a5f20061822f00f0801060a2df64b28b5ebebab/rq_project/rq_worker.png)


###  FailedQueue 实例

``FailedQueue`` 继承自 ``Queue`` 类，它主要增加了 ``quarantine`` 和 ``requeue`` 两个方法。

``quarantine`` 方法将执行失败的 ``Job`` 实例加进执行失败的队列中（默认队列名为 ``'failed'``）。

``requeue`` 则将 ``Job`` 实例重新放回到原本执行它的那个队列中去，等待下一次重新执行。
