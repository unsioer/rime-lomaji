# rime-lomaji

Rime Bân-lâm-gú Lô-má-jī su-ji̍p hong-àn.  
Rime 閩南語羅馬字輸入方案。

Bo̍k-tsiân tsi-tshî/tsi-uān **Tâi-lô** kah **Pe̍h-ōe-jī**.  
目前支持/支援**臺羅**佮**白話字**。

## 特色

* 自動補充連字符 `-`
* 自動補充閬空

## 輸入方案

下底兩款輸入方案（schema）共用 `lomaji` 詞典佮 OpenCC 轉換、Lua 跤本（script）。

| schema | prism | 聲調輸入 |
| --- | --- | --- |
| `lomaji` | `lomaji_nature` | `1`–`9` 直透指定聲調，`qwzxdf` 選字 |
| `lomaji_26` | `lomaji_26` | `q`＝2、`w`＝3、`z`＝5、`x`＝6、`d`＝7／8、`f`＝1／4、`v`＝9 |

## TODO

* 詞頻控制
* 漢字提示
* 漳泉腔口語詞
