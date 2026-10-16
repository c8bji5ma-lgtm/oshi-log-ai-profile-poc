# Issue #68：Gemini / OpenAI 比較用PoC

既存の[共通JSON v1](contract.md)を変更せず、同じ架空データ・画像メタデータ・雰囲気指示からレイアウトJSONを取得するローカルCLI。Rails・DB・既存カード機能には接続しない。今回はAPIキーを作成せず、モックとHTTPスタブだけで実装・検証する。

## 今回のファイル変更

| パス | 役割 |
| --- | --- |
| `lib/ai_profile_poc/providers/{base,gemini,open_ai,mock}.rb` | provider共通インターフェース、API別のリクエスト／応答変換、モック |
| `lib/ai_profile_poc/{provider_factory,provider_error,transport}.rb` | provider切替、匿名化したエラー、HTTP通信と締切 |
| `lib/ai_profile_poc/{comparison_input,layout_schema}.rb` | 許可した共通入力と両APIへ渡すスキーマ |
| `lib/ai_profile_poc/{comparison,request_budget,pricing}.rb` | 共通検証・計測、再試行／回数制限、推定コスト |
| `script/compare_ai_profile_providers.rb` | 比較CLI |
| `spec/lib/ai_profile_providers_spec.rb` | HTTPスタブとCLIのRSpec |
| `docs/ai_profile_poc/image_metadata.json` | ダミー画像のID・幅・高さ |
| `docs/ai_profile_poc/comparison.md` | この資料 |
| `docs/ai_profile_poc/contract.md` | この資料へのリンクを追記 |

新規16ファイル、前回PoC資料1ファイルに追記。既存の `Layout` / `Renderer` / モックJSONと、Issue #26の実装は変更していない。

## 実行

```sh
# 標準：両provider × 3種類。APIキーが存在してもHTTP通信しない。
bundle exec ruby script/compare_ai_profile_providers.rb

# 同じ自由文・スタイルを両providerへ渡す
bundle exec ruby script/compare_ai_profile_providers.rb --style live --mood 'ライブ感を強く、写真を大きめに'

# 片方だけを検証する
bundle exec ruby script/compare_ai_profile_providers.rb --provider gemini --style magazine

# オプション一覧
bundle exec ruby script/compare_ai_profile_providers.rb --help
```

標準出力にmode・妥当性・所要時間・推定USDを表示。既定の出力先は `tmp/ai_profile_poc/comparisons/<UTC日時>-<乱数>/`。`metrics.jsonl` と、有効だった `<style>-<provider>.json` を保存する。`--output DIRECTORY` で出力先を指定できるが、過去の結果を混ぜたり上書きしたりしないよう空ディレクトリに限定する。失敗した行があればCLI終了コードは1。

モックは前回の `mocks/*.json` を返す。自由文の解析やproviderごとの生成品質の差は再現しない。モック時の時間はローカル処理時間、コスト0は外部通信を行わなかった実行の値であり、実モデルの速度・料金ではない。

## 実APIへ切り替える場合

今回は実API呼び出しを行っていない。後日、実行者が安全に設定した環境変数を使い、`--live` を明示した場合に限り外部通信する。キーは環境変数からのみ取得し、`.env` ファイルを自動読込しない。キーの新規作成・保存処理は含めない。

| 環境変数 | 内容 |
| --- | --- |
| `GEMINI_API_KEY` / `OPENAI_API_KEY` | 対応providerの認証キー |
| `GEMINI_MODEL` / `OPENAI_MODEL` | 比較対象のモデルID。キーがある実通信では必須。モデルは未選定で、既定値なし |
| `GEMINI_INPUT_USD_PER_MILLION` / `OPENAI_INPUT_USD_PER_MILLION` | 選択モデルの入力100万トークン単価（USD） |
| `GEMINI_OUTPUT_USD_PER_MILLION` / `OPENAI_OUTPUT_USD_PER_MILLION` | 選択モデルの出力100万トークン単価（USD） |

```sh
# 環境変数が別途設定済みの場合だけ実通信。未設定のproviderはmock。
bundle exec ruby script/compare_ai_profile_providers.rb --live --style live
```

キー未設定のproviderは `--live` でもmockとなる。一方、認証失敗・タイムアウト・不正JSONなどの実通信失敗をmock成功に置き換えることはしない。片方だけキーがある場合はliveとmockが混在するので、必ず出力のmodeを確認する。

## 共通入力とAPI差分

- 共通入力：`activities.json` の活動ID・タイトル・日付・推し名・画像ID、`image_metadata.json` の画像ID・向き補正後の幅／高さから計算した縦横比、スタイル、雰囲気指示、キャンバス寸法。
- 送信する活動フィールドを許可リストで抽出する。所有者ID、添付情報、URL、画像パス、画像バイト列は送信しない。画像メタデータの未知キーも拒否する。CLIでは架空データのみを読み、画像のデコードや実データ取得を行わない。
- 両providerへ同じテキストと `LayoutSchema.build` のスキーマを渡す。OpenAIはResponses APIの `text.format`、GeminiはgenerateContentの `generationConfig.responseFormat` を使用する。[OpenAI公式資料](https://developers.openai.com/api/docs/guides/structured-outputs?api-mode=responses)、[Gemini公式資料](https://ai.google.dev/gemini-api/docs/generate-content/structured-output?hl=en)（2026-10-16確認）。モデルごとの対応可否は実APIでの確認が必要。
- 共通wireスキーマはオブジェクト形状・型・列挙・基本範囲を指定する。色の形式、画像の所属、画像数、枠の端、文字枠の高さは既存 `Layout` で検証し、スタイル一致とクロップの原画像内判定も行う。中断・拒否応答は、JSONが含まれていても成功扱いしない。
- 生成JSONは同じRendererに渡せる形式だが、この比較CLIはPNG合成しない。文字の実測幅・見た目・重なり・読みやすさは別途ローカル合成と目視で評価する。

## 通信の上限

以下は比較PoCの暫定設定であり、本番運用方針の確定ではない。

| オプション | 既定値 | 許容範囲／意味 |
| --- | --- | --- |
| `--timeout` | 20秒 | 1〜60秒。1試行全体の締切に加え、接続・読込・書込にも設定 |
| `--retries` | 1回 | 0〜2回。最大試行数は1+再試行上限 |
| `--max-requests` | 6回 | 1〜20回。CLI全体で両providerの実HTTP試行を合計。失敗・再試行も数える |
| `--per-minute` | 3回 | 1〜20回。provider別の直近60秒の実HTTP試行数。再試行も数える |
| `--max-output-tokens` | 4096 | 256〜8192。両providerへ同じ数値を設定 |

毎分制限は `tmp/ai_profile_poc/request_limits.json` に記録し、ファイルロックでCLIプロセス間でも共有する。上限到達時は待たずにエラーを記録し、その試行を送信しない。壊れた台帳も通信を止める。これはローカルCLI用で、複数ホスト向けの制限や日次・月次の課金上限ではない。

再試行するのはタイムアウト・通信障害・HTTP 429/500/502/503/504のみ。待機は0.5秒、次は1秒。Net::HTTP内部の再試行は無効。認証エラー・中断／拒否・不正JSON／レイアウトは再試行しない。リダイレクトは追従せず、HTTP応答は1 MiBまで、レイアウトJSONは従来どおり64 KiBまで。

## 記録項目と比較方法

`metrics.jsonl` の各行に、provider・mode・要求／応答モデル、スタイル、入力とスキーマのSHA-256、上限設定、JSON／レイアウト妥当性、エラーコード、全体所要時間、各試行の所要時間・トークン数・推定コストを記録する。プロンプト本文、キー、HTTP応答本文、不正な生成JSONは記録しない。

1. 同じスタイルで `input_sha256` と `schema_sha256` が一致する行を組にする。`mode=live` 同士のみを実モデル比較に使う。
2. `json_valid`（JSONとして解釈可能）と `layout_valid`（意味的制約も通過）を比較する。応答が得られない場合の `json_valid=null` は未評価。失敗行も母数に含めて成功率を計算する。
3. `elapsed_ms` は再試行・待機・検証を含む全体時間。`attempts[].elapsed_ms` で試行ごとのAPI処理時間を確認する。両providerは逐次実行なので、同じ条件で複数回測定して分布を見る。
4. 推定コストは `(入力数×入力単価 + 出力数×出力単価) / 1,000,000`。単価は料金表の固定値を埋め込まず、選択モデルの確認済み単価を設定して記録する。OpenAIの出力トークン数、Geminiの候補+思考トークン数を使用する。[OpenAIトークン資料](https://developers.openai.com/api/docs/guides/token-counting)、[Gemini usageMetadata](https://ai.google.dev/api/generate-content#UsageMetadata)。
5. 単価／usageが欠けた試行、タイムアウト等で課金が不明の試行はコスト不明。全試行が計算可能なときだけ `estimated_cost_usd` を出す。`known_cost_usd` は計算できた部分の合計、`cost_complete=false` なら総額として扱わない。キャッシュ割引・無料枠・税・段階料金は反映せず、請求額とは異なる概算。

同じ上限数値でもtokenizer・モデル既定の推論設定はprovider間で異なる。seedやtemperatureを強制していない。モデルID・単価・実行条件を記録し、品質とコストを実測してから採用を判断する。

## 検証と未実施事項

```sh
bundle exec rspec spec/lib/ai_profile_poc_spec.rb spec/lib/ai_profile_providers_spec.rb
bin/rubocop --cache false
bin/rails zeitwerk:check
```

外部送信内容、同一入力／スキーマ、モック切替、応答解析、タイムアウト、再試行上限、共有回数制限、JSON妥当性、コストの既知／不明、CLI出力をHTTPスタブで検証する。実モデルの応答品質・処理速度・料金・利用可能性・利用規約／データ保持条件は未検証。正式UI・実データ連携・モデル採用はこのPoCの対象外。

検証結果（2026-10-16）：

- PoC関連RSpec：88件、失敗0。
- 全件RSpec：1338件、失敗0（8分38秒）。初回はサンドボックスのDB接続制限で停止したため、権限付きで再実行した。前回失敗した既存カードのブラウザテストも今回は成功。ログは `/tmp/oshilog-issue68-provider-rspec.log`。
- RuboCop：新規テストの空白違反1件を修正後、159ファイル、違反0。
- Zeitwerk：`All is good!`。
- CLI：両provider×3種類の6件で共通JSON検証成功。自由文を指定した両providerの実行でも入力SHA-256が一致。APIキー未設定時の `--live` でのmock動作はHTTPスタブ／CLIテストでも検証。
- 実API呼び出し・キー作成・画像の外部送信は行っていない。既存アプリ・元リポジトリ・DB設計への変更、commit・push・PR作成も行っていない。
