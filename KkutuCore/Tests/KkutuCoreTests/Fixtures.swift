@testable import KkutuCore

/// 실제 단어와 가짜 단어가 섞인 작은 사전. 각 줄: 단어 \t 품사 \t 플래그
let fixtureTSV = """
사과\t1,1\t0
사사\t1\t0
과자\t1,1\t0
과히\t8\t0
자동차\t1\t0
차표\t1\t0
표범\t1\t0
표고\t1\t4
범인\t1\t0
인간\t1\t0
기린\t1,1\t0
린스\t1\t1
녀자\t1\t32
여자\t1,1\t0
라면\t1,14,0\t0
나무\t1\t0
무지개\t1\t0
개굴개굴\t6\t0
개나리꽃\t1\t0
어인정단어\tINJEONG\t2
하다\t5\t0
가가\t1\t0
가게\t1\t0
"""

func fixtureIndex() -> WordIndex { WordIndex.parse(tsv: fixtureTSV) }

/// 항상 0을 돌려주는 난수 생성기. 무작위 선택이 항상 첫 원소가 되게 한다.
struct ZeroRNG: RandomNumberGenerator {
    mutating func next() -> UInt64 { 0 }
}
