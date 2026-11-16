/*
 * ★ [SIM] ZeroTier C API 模拟器桩(x86_64 模拟器构建专用)
 *
 * 背景:仓库里的 zt.framework 只有 arm64 切片(Natives/external/ZeroTierFramework/
 * ios-example-app),Intel 模拟器(x86_64)链接主程序时会因架构不符产生大量
 * undefined zts_* 符号。本文件在模拟器构建下由 CMakeLists.txt 编进主程序,
 * 以同名 no-op 实现替代 -framework zt,让联机相关代码(ZeroTierBridge /
 * MultiplayerManager / SOCKS5Proxy / PortForwarder)可正常编译链接;
 * 运行时 ZeroTier 节点不可用(node_start 返回 ZTS_ERR_SERVICE,socket 全部 -1),
 * 联机功能在模拟器上表现为"不可用/连接失败",UI 其余功能不受影响。
 *
 * 设备构建不编译本文件,仍链接真 zt.framework,行为零变化。
 *
 * 原型与 external/ZeroTierFramework/ios-example-app/zt.framework/Headers/
 * ZeroTierSockets.h 逐一对应;仅覆盖 App 代码实际调用的符号
 * (grep 'zts_' Natives --include='*.m' 的并集)。
 */
#include "ZeroTierSockets.h"

#include <arpa/inet.h>
#include <stddef.h>
#include <stdint.h>
#include <stdio.h>
#include <sys/types.h>

/* zts_errno 是 libzt 导出的全局错误码变量(ZeroTierSockets.h: extern int zts_errno)。 */
int zts_errno = ZTS_ERR_SERVICE;

/* ---------------------------------------------------------------------------
 * 节点生命周期:模拟器上直接报告服务不可用,节点永远 offline。
 * ------------------------------------------------------------------------- */
int zts_node_start(void) {
    static int warned = 0;
    if (!warned) {
        warned = 1;
        fprintf(stderr, "[zt-sim-stub] ZeroTier is stubbed on the iOS simulator "
                        "(zt.framework has no x86_64 slice); multiplayer unavailable.\n");
    }
    zts_errno = ZTS_ERR_SERVICE;
    return ZTS_ERR_SERVICE;
}

int zts_node_stop(void) {
    return ZTS_ERR_OK;
}

int zts_node_is_online(void) {
    return 0;
}

uint64_t zts_node_get_id(void) {
    return 0;
}

int zts_init_from_storage(const char *path) {
    (void)path;
    return ZTS_ERR_SERVICE;
}

int zts_init_set_event_handler(void (*callback)(void *)) {
    /* 收下回调但永不触发事件:调用方会一直停留在"节点未上线"状态。 */
    (void)callback;
    return ZTS_ERR_OK;
}

/* ---------------------------------------------------------------------------
 * 网络加入/离开与状态查询。
 * ------------------------------------------------------------------------- */
int zts_net_join(uint64_t net_id) {
    (void)net_id;
    zts_errno = ZTS_ERR_SERVICE;
    return ZTS_ERR_SERVICE;
}

int zts_net_leave(uint64_t net_id) {
    (void)net_id;
    return ZTS_ERR_OK;
}

int zts_net_transport_is_ready(const uint64_t net_id) {
    (void)net_id;
    return 0;
}

uint64_t zts_net_compute_adhoc_id(uint16_t start_port, uint16_t end_port) {
    /* 纯算术函数,按 libzt 原实现语义本地计算,不需要服务:
     * 高两字节 = start_port,次两字节 = end_port,低字节固定 0xff
     * (ZeroTierSockets.h 约定 Ad-hoc ID 最低字节必须为 0xff)。 */
    uint64_t adhocId = 0;
    adhocId |= (uint64_t)start_port << 48;
    adhocId |= (uint64_t)end_port << 32;
    adhocId |= 0xffull;
    return adhocId;
}

/* ---------------------------------------------------------------------------
 * 地址查询。
 * ------------------------------------------------------------------------- */
int zts_addr_is_assigned(uint64_t net_id, unsigned int family) {
    (void)net_id;
    (void)family;
    return 0;
}

int zts_addr_get_str(uint64_t net_id, unsigned int family, char *dst, unsigned int len) {
    (void)net_id;
    (void)family;
    if (dst && len > 0) {
        dst[0] = '\0';
    }
    return ZTS_ERR_SERVICE;
}

/* ---------------------------------------------------------------------------
 * BSD socket 兼容层:全部返回失败(socket 创建即失败,
 * 上层 SOCKS5 代理/端口转发会走错误分支)。
 * ------------------------------------------------------------------------- */
int zts_bsd_socket(int family, int type, int protocol) {
    (void)family; (void)type; (void)protocol;
    zts_errno = ZTS_ERR_SERVICE;
    return -1;
}

int zts_bsd_bind(int fd, const struct zts_sockaddr *addr, zts_socklen_t addrlen) {
    (void)fd; (void)addr; (void)addrlen;
    return -1;
}

int zts_bsd_listen(int fd, int backlog) {
    (void)fd; (void)backlog;
    return -1;
}

int zts_bsd_accept(int fd, struct zts_sockaddr *addr, zts_socklen_t *addrlen) {
    (void)fd; (void)addr; (void)addrlen;
    return -1;
}

int zts_bsd_connect(int fd, const struct zts_sockaddr *addr, zts_socklen_t addrlen) {
    (void)fd; (void)addr; (void)addrlen;
    zts_errno = ZTS_ERR_SERVICE;
    return -1;
}

int zts_bsd_close(int fd) {
    (void)fd;
    return -1;
}

int zts_bsd_shutdown(int fd, int how) {
    (void)fd; (void)how;
    return -1;
}

int zts_bsd_setsockopt(int fd, int level, int optname, const void *optval, zts_socklen_t optlen) {
    (void)fd; (void)level; (void)optname; (void)optval; (void)optlen;
    return -1;
}

int zts_bsd_getsockopt(int fd, int level, int optname, void *optval, zts_socklen_t *optlen) {
    (void)fd; (void)level; (void)optname; (void)optval; (void)optlen;
    return -1;
}

int zts_bsd_fcntl(int fd, int cmd, int flags) {
    (void)fd; (void)cmd; (void)flags;
    return -1;
}

ssize_t zts_bsd_send(int fd, const void *buf, size_t len, int flags) {
    (void)fd; (void)buf; (void)len; (void)flags;
    return -1;
}

ssize_t zts_bsd_recv(int fd, void *buf, size_t len, int flags) {
    (void)fd; (void)buf; (void)len; (void)flags;
    return -1;
}

int zts_bsd_select(int nfds, zts_fd_set *readfds, zts_fd_set *writefds,
                   zts_fd_set *exceptfds, struct zts_timeval *timeout) {
    (void)nfds; (void)readfds; (void)writefds; (void)exceptfds; (void)timeout;
    return -1;
}

/* ---------------------------------------------------------------------------
 * 地址字符串转换:转发系统 libc 实现(语义一致)。
 * ------------------------------------------------------------------------- */
const char *zts_inet_ntop(int family, const void *src, char *dst, zts_socklen_t size) {
    return inet_ntop(family, src, dst, size);
}

int zts_inet_pton(int family, const char *src, void *dst) {
    return inet_pton(family, src, dst);
}
