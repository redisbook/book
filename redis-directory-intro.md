#源码目录介绍


    hoterran@~/Projects/redis-2.4.16$ tree -L 1
    .
    |-- 00-RELEASENOTES
    |-- BUGS
    |-- CONTRIBUTING
    |-- COPYING
    |-- deps
    |-- INSTALL
    |-- Makefile
    |-- README
    |-- redis.conf
    |-- runtest
    |-- src
    |-- tests
    `-- utils


##deps

    hoterran@~/Projects/redis-2.4.16$ tree deps/ -L 1
    deps/
    |-- hiredis
    |-- jemalloc
    `-- linenoise


###hiredis

Redis 的c api，编译 Redis 官方客户端``redis-client``，工具``redis-checkaof``都需要使用它。

api 包含了处理网络的``net.c``，包含多种多路复用的``adapters``目录，动态字符串``sds.c``，处理哈希结构的``dict.c``。


###jemalloc

2.4 版本之后，Redis 开始使用了``facebook``工程师出品的``jemalloc`` 来做内存管理，``jemalloc``从各方评测的结果可见与``google``工程师出品的``tcmalloc``都不相伯仲，皆为内存管理器领域最高水平。


###linenoise

命令行行编辑管理工具。


##src

源码目录


##tests

tcl吐槽


##utils

Redis 辅助工具，例如打包，初始化脚本。




