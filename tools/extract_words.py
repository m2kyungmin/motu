#!/usr/bin/env python3
"""끄투 db.sql에서 kkutu_ko 단어를 뽑아 words.tsv(단어\t품사\t플래그\t주제)를 만든다. 주제 0(없음)은 빈칸.

사용: extract_words.py <db.sql> <words.tsv>   |   extract_words.py --selftest
"""
import sys

HEADER = "COPY kkutu_ko (_id, type, mean, hit, flag, theme) FROM stdin;"


def extract(lines):
    inside = False
    for line in lines:
        line = line.rstrip("\n")
        if not inside:
            if line == HEADER:
                inside = True
            continue
        if line == "\\.":
            return
        cols = line.split("\t")
        if len(cols) != 6:
            raise ValueError(f"6컬럼이 아님: {line!r}")
        word, typ, _mean, _hit, flag, theme = cols
        theme = "" if theme == "0" else theme
        yield f"{word}\t{typ}\t{flag}\t{theme}"


def selftest():
    sample = [
        "-- junk\n",
        HEADER + "\n",
        "사과\t1,1\t＂1＂［1］（1）\t0\t0\t270,320\n",
        "린스\t1\t＂1＂［1］（1）\t0\t1\t0\n",
        "\\.\n",
        "COPY other (a) FROM stdin;\n",
        "x\n",
        "\\.\n",
    ]
    out = list(extract(sample))
    assert out == ["사과\t1,1\t0\t270,320", "린스\t1\t1\t"], out
    print("selftest ok")


if __name__ == "__main__":
    if len(sys.argv) == 2 and sys.argv[1] == "--selftest":
        selftest()
        sys.exit(0)
    if len(sys.argv) != 3:
        print(__doc__)
        sys.exit(2)
    n = 0
    with open(sys.argv[1], encoding="utf-8") as src, open(sys.argv[2], "w", encoding="utf-8") as dst:
        for row in extract(src):
            dst.write(row + "\n")
            n += 1
    print(f"{n} words")
