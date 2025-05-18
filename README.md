# Search PoC D

高速な単語検索エンジンのD言語実装（実験）

## 概要

このプロジェクトは、大量の単語データを効率的に検索するためのツールです。BK-Tree（Burkhard-Keller Tree）と最適化されたデータ構造を使用して、高速な類似検索を実現しています。

主な特徴：

- 10万件以上の単語に対する高速検索機能
- 前方一致/後方一致/部分一致検索
- 編集距離に基づく類似単語検索
- インデックスによる検索の高速化
- 詳細な検索時間測定と表示

## 機能

### 検索モード

| コマンド | 説明 | 例 |
|---------|------|-----|
| `:pre` / `:prefix` | 前方一致検索 | `:pre app` |
| `:suf` / `:suffix` | 後方一致検索 | `:suf ing` |
| `:sub` / `:substr` | 部分一致検索 | `:sub cat` |
| `:exact` / `:eq` | 完全一致検索 | `:exact apple` |
| `:sim` / `:similar` | 類似検索 | `:sim apple 2` |
| `:sim+` | 拡張類似検索（より多くの結果） | `:sim+ apple 2` |
| `:complex` / `:comp` | 複合検索 | `:complex pre:a suf:z len:3-5` |

### その他のコマンド

| コマンド | 説明 |
|---------|------|
| `:h` / `:help` | ヘルプを表示 |
| `:exit` / `:quit` | プログラムを終了 |
| `:delete ID` / `:d ID` | 指定IDの単語を削除 |
| `:undelete ID` / `:u ID` | 削除した単語を復元 |
| `:list` / `:l` | 登録単語一覧を表示 |
| `:list-all` / `:la` | 削除済みを含む全単語を表示 |
| `:alpha` / `:a` | 単語をアルファベット順に表示 |
| `:rebuild` / `:reindex` | インデックスを再構築 |

## インストール

### 必要条件

- D言語コンパイラ（DMD, LDC, GDCのいずれか）
- DUB（Dパッケージマネージャ）

### ビルド方法

標準ビルド:

```
dub build --force --compiler=dmd -a=x86_64 -b=release -c=application --build-mode=allAtOnce
```

最適化ビルド:

```
DFLAGS="-O -inline -release -boundscheck=off -mcpu=native" dub build --force --compiler=dmd -a=x86_64 -b=release -c=application --build-mode=allAtOnce
```

### VSCodeでのビルド

このプロジェクトには、VSCode用のタスク構成が含まれています。VSCodeでタスクパレット（Ctrl+Shift+P）を開き、「Tasks: Run Task」を選択して以下のタスクを実行できます：

- `dub: Build` - 標準最適化ビルド
- `dub: Optimized Build` - 超最適化ビルド
- `Run: Standard Version` - 標準ビルド版を実行
- `Run: Optimized Version` - 超最適化版を実行

## 使用方法

1. プログラムを起動する：

   ```
   ./search-poc-d
   ```

2. 単語を追加する（スペース区切りで複数可能）：

   ```
   > apple banana orange
   単語「apple」をIDは0でCSVに追加しました
   単語「banana」をIDは1でCSVに追加しました
   単語「orange」をIDは2でCSVに追加しました
   ```

3. 検索を実行する：

   ```
   > :sim apple 2
   類似検索: "apple" (距離<=2)
   ID:0  距離:0  apple
   ID:235  距離:2  aple
   ID:1022  距離:2  applet
   合計: 3件 (通常モード)
   検索時間: 0.005436秒 (5.436ミリ秒 = 5436マイクロ秒)
   ```

## 技術的詳細

### BK-Tree検索

BK-Tree（Burkhard-Keller Tree）は、メトリック空間内での近似検索を効率化するデータ構造です。このプロジェクトでは、Damerau-Levenshtein距離を用いて、単語間の編集距離を計算しています。

特徴：

- 平均的にO(log n)に近い検索時間
- 三角不等式を利用した枝刈りによる効率化
- インデックス構築時間を短縮するメモリ最適化

### インデックス構造

- 前方一致: RedBlackTree（平衡二分木）
- 後方一致: 逆順文字列のRedBlackTree
- 部分一致: n-gramインデックス＋BitArray
- 長さ検索: 長さごとのIDマップ

### データファイル

このプログラムは、単語データを永続化するためにCSVファイルを使用します：

#### language_data.csv
```

   ./search-poc-d --generate-data <件数>
```
上記コマンドを実行することでカレントディレクトリに作成される主要なデータファイル。プログラム終了後もデータが保持されます。

- **構造**: ID,単語,削除フラグ
- **例**:
  ```
  ID,単語,削除フラグ
  0,apple,0
  1,banana,0
  2,orange,0
  3,grape,1
  ```

- 削除フラグ: `0` = 有効, `1` = 削除済み
- 論理削除のため、削除された単語もファイルには残りますが、検索結果には表示されません

#### キャッシュファイル

初回読み込み速度を向上させるためのキャッシュファイルも自動的に生成されます：

- **language_data.csv.cache**: インデックスのバイナリキャッシュ
- CSVファイルよりも新しい場合のみ使用されます
- 手動で削除しても問題ありません（再生成されます）

注意：大規模な辞書（10万語以上）を使用する場合、CSVファイルとキャッシュファイルが大きくなることがあります。定期的なバックアップをお勧めします。

## ライセンス

MIT

## 今後の課題

- テストを書く
- マルチスレッド検索の実装
- GUIインターフェースの追加
- 外部辞書からのインポート機能
- 検索結果のエクスポート機能