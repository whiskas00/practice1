"""Мини-помощник для демо-сценариев: выполняет SQL через Trino и пишет лог в Markdown
(запрос + вывод), чтобы в results/ лежало ровно то, что я видела в консоли."""
import os, subprocess

ROOT = os.path.dirname(os.path.dirname(os.path.abspath(__file__)))
TRINO = os.path.join(ROOT, "scripts", "trino.sh")


def q(sql, fmt="TSV"):
    r = subprocess.run([TRINO, sql, "--output-format", fmt], capture_output=True, text=True)
    if r.returncode != 0:
        raise RuntimeError(r.stderr.strip())
    return r.stdout.strip()


def val(sql):
    return q(sql).splitlines()[0].split("\t")[0]


class Log:
    def __init__(self, path, title):
        self.path = path
        self.f = open(path, "w")
        self.f.write(f"# {title}\n\n")

    def text(self, s):
        self.f.write(s + "\n\n")
        print(s)

    def run(self, title, sql, allow_fail=False):
        self.f.write(f"### {title}\n\n```sql\n{sql.strip()}\n```\n\n")
        try:
            out = q(sql, "ALIGNED")
        except RuntimeError as e:
            if not allow_fail:
                raise
            out = "ОШИБКА: " + str(e).splitlines()[0]
        self.f.write(f"```\n{out}\n```\n\n")
        self.f.flush()
        print(f"--- {title}\n{out}\n")
        return out

    def close(self):
        self.f.close()
