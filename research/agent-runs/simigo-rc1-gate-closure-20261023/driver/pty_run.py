import os, sys, pty, select, errno
# usage: pty_run.py LOGFILE -- KEY=VAL ... PROGCMD [args...]
logfile = sys.argv[1]
assert sys.argv[2] == "--"
argv = sys.argv[3:]
env = dict(os.environ)
i = 0
while "=" in argv[i]:
    k, v = argv[i].split("=", 1)
    env[k] = v
    i += 1
cmd = argv[i:]
lf = open(logfile, "wb")
pid, fd = pty.fork()
if pid == 0:
    os.execve(cmd[0], cmd, env)
    os._exit(127)
data = b""
while True:
    try:
        r, _, _ = select.select([fd], [], [], 1800)
        if not r: break
        chunk = os.read(fd, 65536)
        if not chunk: break
        data += chunk
        lf.write(chunk); lf.flush()
    except OSError as e:
        if e.errno == errno.EIO: break
        raise
lf.close()
_, status = os.waitpid(pid, 0)
rc = os.waitstatus_to_exitcode(status) if hasattr(os, "waitstatus_to_exitcode") else (status >> 8)
print("PTY_CHILD_RC=%d bytes=%d" % (rc, len(data)))
sys.exit(rc)
