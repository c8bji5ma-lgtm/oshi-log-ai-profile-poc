# Issue #68 オフラインPoC：共通レイアウトJSON v1

この仕様は技術検証用の暫定契約。Issue #26の3種類・12配置・クロップ・認可・一時保存仕様とは独立している。外部AI APIや実データは使わない。モデル選定、画像送信、正式UIの採用は未決定。

共通JSON v1をそのまま使う追加のprovider比較実装は [Gemini / OpenAI比較用PoC](comparison.md) を参照。このオフラインスクリプトの動作は変更しない。

## 入力と再現方法

`activities.json` は架空の所有者・活動日・活動タイトル・推し名・画像IDの対応表。日付は検証を再現できる固定値。`AiProfilePoc::DummyImages.build` は人物のいないライブ会場・レコード・グッズの図形ダミーPNGをローカル生成する。実際の活動DBやActive Storageには接続しない。

```sh
bundle exec ruby script/ai_profile_poc.rb
bundle exec rspec spec/lib/ai_profile_poc_spec.rb
```

出力はGit管理対象外の `tmp/ai_profile_poc/`：ダミー原画像3枚と `live.png`、`magazine.png`、`scrapbook.png`。PNGは1200×1500、RGB。原画像のSHA-256が生成前後で一致することも検証する。

## JSONの共通契約

JSON文書は最大64 KiB、パース深度は最大12。全オブジェクトで下表のキーのみを必須とし、未知のキーも欠損キーも拒否する。数値文字列や小数座標は受け付けない。配列の順序が描画順（後ろほど手前）。任意のHTML、SVG、コード、フォント、パス、URL、画像バイト列は契約に含めない。

| ルートキー | 許容値 |
| --- | --- |
| `version` | 整数 `1` |
| `style` | `live` / `magazine` / `scrapbook` |
| `background` | `#RRGGBB`（大文字・小文字可） |
| `elements` | 1〜32要素。うち画像は1〜6枚 |

全要素に `type`, `x`, `y`, `width`, `height` を指定する。座標はキャンバス左上原点の整数ピクセル。幅・高さは正の整数、矩形全体が1200×1500の内側に収まる必要がある。重なりは装飾・コラージュのため許容する。

| `type` | 追加の必須キー | 制約 |
| --- | --- | --- |
| `rect` | `color` | 不透明な単色矩形。色は `#RRGGBB` |
| `image` | `activity_id`, `image_id`, `crop` | 幅・高さ各64px以上。選択された本人の活動と、その活動に属する許可画像IDを参照 |
| `text` | `activity_id`, `field`, `size`, `color` | `field` は `title` / `occurred_on` / `oshi_names` のみ。サイズ16〜64の整数、色は `#RRGGBB`。高さはサイズ+8px以上 |

`crop` の必須キーは数値の `x`, `y`, `zoom` のみ。`x`, `y` は向き補正後の画像に対する表示範囲の中心（0〜1）、`zoom` は全面を埋める倍率を基準に1〜3。座標型・範囲はLayoutで確認し、画像寸法から見切れ範囲が原画像の外に出ないかはRendererで確認する。不正な範囲を黙って補正しない。

```json
{
  "version": 1,
  "style": "live",
  "background": "#17112B",
  "elements": [
    {
      "type": "image", "x": 72, "y": 170, "width": 1056, "height": 570,
      "activity_id": "activity-live", "image_id": "photo-live",
      "crop": {"x": 0.5, "y": 0.5, "zoom": 1}
    }
  ]
}
```

文字はAIが書いた自由文ではなく、参照先の登録データから描画時に解決する。タイトルは1〜255文字、実在日付のISO形式 `YYYY-MM-DD`、推し名は1〜4件・各1〜50文字。空白のみ・制御文字・欠損を含む参照データはこのPoCでは拒否する。推し名配列は ` / ` で連結する。日本語フォントはサーバー固定、Pangoのマークアップをエスケープし、1行の枠に収まらない文字列を末尾 `…` で省略する。省略記号自体が収まらない枠も拒否する。欠損時の正式なUXは未確定。

実装上の契約は `lib/ai_profile_poc/layout.rb`。`Layout::Invalid` の場合はPNGを返さない。既定デザインへの自動復帰やUIでの再試行案内はこのPoCには含めない。

## 同一素材による3つのモック

`mocks/*.json` はAI応答を手書きで代用した決定的なモック。自由文の解析・自動提案やスタイルの品質判定は行っていない。`style` は識別ラベルで、全スタイルで共通の要素と検証・描画処理を使う。

| モック | 表現 |
| --- | --- |
| `live`（ライブ感） | 暗い紫、鮮やかなピンクと黄緑、横長の大きな写真、太い見出し |
| `magazine`（雑誌風） | 生成り背景、余白、主写真と細い右カラム、控えめな罫線 |
| `scrapbook`（スクラップブック風） | 紙色背景、白い写真台紙、ずらした配置、色付きテープを模した矩形 |

## 検証の境界と残課題

- 所有者ID・活動ID・画像IDの対応を検証し、描画には呼出元が渡した画像バイト列だけを使う。JSONから画像ファイルを読んだりネットワークへアクセスしたりしない。
- これはダミー入力に対する対応関係の検証であり、実ユーザーの認証・DBスコープによる認可の実装ではない。正式実装では認証済みユーザーの活動と保護された画像読込経路に接続する必要がある。
- 画像のデコード前サイズ・容量・形式制限、一時保存期限、データ変更検知、実データでの画質・文字量、再生成／確認／PNG保存UIは未検証。現在は固定サイズの信頼済みダミーPNGだけを生成するローカルスクリプト。
- モデル・料金・API上限・タイムアウト・再試行・画像送信条件・同意・データ保持方針は未決定。外部AIサービスへの送信は行っていない。
- 新規DB、マイグレーション、ルート、既存カードサービス／UI、Gem追加は不要。原画像を加工して上書きする処理もない。

## 検証記録（2026-10-16）

- `bundle exec ruby script/ai_profile_poc.rb`：ダミー原画像3枚・合成PNG3枚の生成成功。原画像SHA-256不変。3種類とも目視確認済み。
- `bundle exec rspec spec/lib/ai_profile_poc_spec.rb`：58件、失敗0。JSONの不正値・所有者／画像対応・欠損・クロップ範囲・文字のエスケープ／省略・合成画素・原画像保持を検証。
- `bin/rubocop --cache false`：145ファイル、違反0。
- `bin/rails zeitwerk:check`：`All is good!`。
- RSpec全件：1308件、失敗1。`spec/system/profiles_and_cards_spec.rb:1094` が、期待した3枚のPNGに加えてChromeの `downloads.html.crdownload` を検出して失敗した（1195行）。同じ環境で該当テストのみ再実行すると1件、失敗0。全件実行時の一時ファイル検出は再発可能性が残る。既存テストは変更していない。
- 全件の初回実行はサンドボックスのPostgreSQL接続制限で停止したため、権限を付けて再実行した。ブラウザは `CHROME_BIN=/opt/google/chrome/chrome`、`SE_CHROMEDRIVER=/home/Yuki0719/.cache/selenium/chromedriver/linux64/151.0.7922.138/chromedriver` を使用。

全件結果ログ：`/tmp/oshilog-issue68-rspec.log`。該当テストの再実行ログ：`/tmp/oshilog-issue68-rspec-retry.log`。
