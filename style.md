# 风格规范


## 格式

文本使用 markdown 格式来书写。

Markdown 的具体细节可以参考 [Markdown 语法说明](http://wowubuntu.com/markdown/) 。


## 标题

Markdown 的标题可以用两种格式来书写：

    # 标题

    标题
    -----

我们选用 ``# 标题`` 风格。


## 空行

为了方便识别，每个标题和上一段正文之间，需要空出至少两行。

比如：

    上一段正文...

    
    # 标题


## 列表

列表使用 ``*`` 符号来标识：

    * 列表项 1
    * 列表项 2
    * 列表项 3


## 代码

代码使用 ``highlight`` 功能进行高亮：

    {% highlight c %}
    void greet(void)
    {
        printf("hello world!\n");
    }
    {% endhighlight %}

省略代码时，要在注释中进行说明：

    {% highlight c %}
    void longFunction(void)
    {
        // 省略 ...
        printf("hello world\n");
        // 省略 ...
    }
    {% endhighlight %}


## 行内代码

语法关键字、文件路径、变量等文字，需要用行内样式标示。

比如：

    ``/home/user/someone``

    ``struct redisClient`` 的 ``lua`` 属性表示 Lua 环境实例


## 数字和英文

夹杂中英文和数字的文本，需要在数字或英文的左右两边放一个空格，左右两边有标点符号包裹除外。

比如：

    Redis 数据库是由 Salvatore Sanfilippo （antirez）开发的一款高性能数据库。

    Redis 的最新稳定版本是 2.4.16 。


## 标点符号

所有文本正文使用中文、全角标点符号。

比如：

    Redis 的作者是 Salvatore Sanfilippo （antirez）。

而不是：

    Redis 的作者是 Salvatore Sanfilippo (antirez). 
