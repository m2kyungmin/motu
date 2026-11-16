#!/usr/bin/env python3
"""우리말샘 JSON 전체 내려받기에서 words.tsv에 없는 단어를 끄투 형식(단어\t품사\t플래그\t주제)으로 덧붙인다.

끄투 kkutu_ko도 예전 우리말샘에서 만든 것이라, 같은 규칙으로 바꾸면 겹치는 단어의 품사·플래그가 거의 그대로 맞는다
(--compare로 확인). 기존 줄은 건드리지 않고(어인정·주제 유지) 새 단어만 파일 끝에 붙인다.
끝말잇기에서 쓰이지 않는 품사(동사·형용사 등, KOR_GROUP 밖)는 넣지 않는다.

사용: merge_opendict.py <json 폴더> <words.tsv>            덧붙이기
      merge_opendict.py --compare <json 폴더> <words.tsv>  겹치는 단어로 변환 규칙 일치율만 출력
      merge_opendict.py --selftest
"""
import glob
import json
import re
import sys

POS = {
    "명사": "1", "대명사": "2", "수사": "3", "조사": "4", "동사": "5", "형용사": "6", "관형사": "7",
    "부사": "8", "감탄사": "9", "접사": "10", "의존 명사": "11", "보조 동사": "12", "보조 형용사": "13",
    "어미": "14", "관·명": "15", "수·관": "16", "명·부": "17", "감·명": "18", "대·부": "19", "대·감": "20",
    "동·형": "21", "관·감": "22", "부·감": "23", "의명·조": "24", "수·관·명": "25", "대·관": "26",
}
KOR_GROUP = {"0", "1", "2", "3", "7", "8", "9", "11", "15", "16", "17", "18", "19", "20", "26"}
LOANWORD, SPACED, SATURI, OLD, MUNHWA = 1, 4, 8, 16, 32
NATIVE_LANGS = {"한자", "고유어", ""}


def sense(item):
    """(단어, 품사 코드, 외래어?, 띄어씀?, 뜻 갈래) 또는 None."""
    wi, si = item["wordinfo"], item["senseinfo"]
    unit = wi.get("word_unit")
    if unit not in ("어휘", "구"):  # 속담·관용구는 끄투에도 없다
        return None
    raw = wi["word"]
    word = raw.replace("-", "").replace("^", "")
    if not re.fullmatch(r"[가-힣]{2,}", word):
        return None
    typ = "0" if unit == "구" else POS.get(si.get("pos"), "0")
    langs = {o.get("language_type", "") for o in wi.get("original_language_info", [])}
    loan = wi.get("word_type") == "외래어" or (wi.get("word_type") == "혼종어" and bool(langs - NATIVE_LANGS))
    return word, typ, loan, "^" in raw or unit == "구", si.get("type")


def collect(folder):
    """단어 → [품사 코드들], 플래그. 파일·항목 순서를 유지한다."""
    words = {}
    for path in sorted(glob.glob(f"{folder}/*.json")):
        with open(path, encoding="utf-8") as f:
            items = json.load(f)["channel"]["item"]
        for item in items:
            s = sense(item)
            if s:
                words.setdefault(s[0], []).append(s[1:])
    return {w: encode(senses) for w, senses in words.items()}


def encode(senses):
    types = [s[0] for s in senses]
    flag = 0
    if any(s[1] for s in senses):
        flag |= LOANWORD
    if any(s[2] for s in senses):
        flag |= SPACED
    kinds = {s[3] for s in senses}
    if "일반어" not in kinds:  # 표준어 뜻이 하나라도 있으면 방언·옛말·북한어로 보지 않는다
        if "방언" in kinds:
            flag |= SATURI
        if "옛말" in kinds:
            flag |= OLD
        if "북한어" in kinds:
            flag |= MUNHWA
    return types, flag


def read_tsv(path):
    out = {}
    with open(path, encoding="utf-8") as f:
        for line in f:
            cols = line.rstrip("\n").split("\t")
            out[cols[0]] = (cols[1].split(","), int(cols[2]))
    return out


def compare(od, kk):
    both = od.keys() & kk.keys()
    same_type = sum(set(od[w][0]) == set(kk[w][0]) for w in both)
    same_group = sum(bool(set(od[w][0]) & KOR_GROUP) == bool(set(kk[w][0]) & (KOR_GROUP | {"INJEONG"})) for w in both)
    print(f"겹침 {len(both)}  품사 일치 {same_type / len(both):.1%}  허용 여부 일치 {same_group / len(both):.1%}")
    for bit, name in [(LOANWORD, "외래어"), (SPACED, "띄어씀"), (SATURI, "방언"), (OLD, "옛말"), (MUNHWA, "문화어")]:
        same = sum(bool(od[w][1] & bit) == bool(kk[w][1] & bit) for w in both)
        print(f"  {name} 일치 {same / len(both):.1%}")


def new_rows(od, kk):
    for w, (types, flag) in od.items():
        if w in kk or not set(types) & KOR_GROUP:
            continue
        yield f"{w}\t{','.join(types)}\t{flag}\t"


def selftest():
    def item(word, unit="어휘", pos="명사", wtype="고유어", kind="일반어", langs=()):
        return {"wordinfo": {"word": word, "word_unit": unit, "word_type": wtype,
                             "original_language_info": [{"language_type": l} for l in langs]},
                "senseinfo": {"pos": pos, "type": kind}}
    assert sense(item("미세^먼지", unit="구", pos=None)) == ("미세먼지", "0", False, True, "일반어")
    assert sense(item("가-성비")) == ("가성비", "1", False, False, "일반어")
    assert sense(item("새발의 피", unit="관용구")) is None
    assert sense(item("가")) is None
    assert sense(item("겨집-다")) is None
    assert sense(item("문자^메시지", unit="구", wtype="혼종어", langs=["한자", "영어"]))[2] is True
    assert sense(item("가성비", wtype="혼종어", langs=["한자"]))[2] is False
    # 일반어 뜻이 있으면 방언 표시를 하지 않는다
    assert encode([("1", False, False, "방언"), ("1", False, False, "일반어")]) == (["1", "1"], 0)
    assert encode([("1", True, True, "방언"), ("8", False, False, "옛말")]) == (["1", "8"], 1 | 4 | 8 | 16)
    kk = {"사과": (["1"], 0)}
    od = {"사과": (["1"], 0), "셀카": (["1"], 1), "먹다": (["5"], 0)}
    assert list(new_rows(od, kk)) == ["셀카\t1\t1\t"]
    print("selftest ok")


if __name__ == "__main__":
    args = sys.argv[1:]
    if args == ["--selftest"]:
        selftest()
    elif len(args) == 3 and args[0] == "--compare":
        compare(collect(args[1]), read_tsv(args[2]))
    elif len(args) == 2:
        od, kk = collect(args[0]), read_tsv(args[1])
        rows = list(new_rows(od, kk))
        with open(args[1], "a", encoding="utf-8") as f:
            f.writelines(r + "\n" for r in rows)
        print(f"{len(rows)} words appended")
    else:
        print(__doc__)
        sys.exit(2)
