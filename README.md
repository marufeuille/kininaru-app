# きになる

iPad で、質問・答え・履歴の 3 画面を行き来する SwiftUI アプリです。S0 は画面の移動だけです。

## 動作環境

| 項目 | 内容 |
| --- | --- |
| 対象 | iPad のみ |
| 最低 OS | iPadOS 17.0 |
| 向き | 縦、横、上下さかさま |
| Bundle ID | `com.marufeuille.kininaru` |
| 署名チーム | 未設定 |

最低 OS を iPadOS 17.0 にしています。2020 年ごろの iPad を、あとから検証機に足せるようにするためです。S0 で実機確認に使うのは 2025 年モデルの iPad です。

## 用意するもの

- Mac
- Xcode 15 以降
- XcodeGen

XcodeGen は次で入ります。

```sh
brew install xcodegen
```

## シミュレータで動かす

1. このリポジトリを開く
2. `xcodegen generate` を実行する
3. `open Kininaru.xcodeproj` で Xcode を開く
4. 実行先を iPad シミュレータにする
5. Run する

`.xcodeproj` は生成物です。リポジトリには入れていません。`project.yml` が正本です。

## 自分の iPad で動かす

1. シミュレータと同じ手順でプロジェクトを開く
2. ターゲット Kininaru の Signing & Capabilities で Team を選ぶ
3. 接続した iPad を実行先にして Run する
4. iPad でデベロッパモードをオンにする。設定、プライバシーとセキュリティ、デベロッパモード
5. 開発元を信頼する。設定、一般、VPN とデバイス管理

Team は手元の Mac だけで設定します。リポジトリのプロジェクトには書きません。

## 計測画面（実機）

S1 の数値は、2025 年の無印 iPad (A16) で取ります。識別子は Wi-Fi が `iPad15,7`、Wi-Fi + Cellular が `iPad15,8` です。シミュレータの秒数とメモリは使いません。

計測は Debug ビルドだけです。Xcode の Run は通常 Debug です。Release には歯車が出ません。計測のコード、同梱の音声と抜粋、音声認識とマイクの利用目的の文も Release には入りません。FoundationModels もリンクしません。製品の Release は、最低の iPadOS 17 で起動します。子ども向けの質問の流れには入れていません。

答えの理由コード（`deviceNotEligible` など）を取るのは、Xcode 26 以降の Debug で、検証機が iPadOS 26 以降のときです。Xcode 16 系の Debug は SDK に FoundationModels が無いので `sdkMissing` になります。Xcode 26 の Debug は FoundationModels を weak link します。その Debug も iPadOS 17 で起動します。iPadOS 26 より前ではモデルを呼ばず、理由は `osTooOld` です。

1. `xcodegen generate` のあと、Xcode でプロジェクトを開く
2. 上の「自分の iPad で動かす」と同じように Team を選び、接続した iPad を実行先にする
3. Debug で Run する
4. 質問画面の左上の歯車を押す
5. 「3回測る」を押す。音声認識の許可を聞かれたら許可する。許可を待っている時間は秒数に入らない
6. 各プローブは 3 回連続で、1 回の中に初回とウォームがある。画面と Markdown の表は、その 3 回の中央値
7. マイクは自動では測らない。測るときは大人が「マイクで4秒測る」を押す。その 4 秒のあいだ日本語で話す。認識した文は計測結果に残るので、子どもには押させない。必要なら 3 回押す
8. 「Markdown をコピー」か「Markdown を共有」で結果を渡す。JSON も同じ場所にある

もう一度測ると、前の結果は置き換わります。マイクの結果は、そのあとに足せます。

同梱の音声は、espeak-ng で作った約 7 秒の日本語です。作り直すときは `bash scripts/generate-speech-sample.sh` です。認識の精度を見るための音ではありません。

## テスト

GitHub Actions は 2 本です。macos-15 の Xcode 16.4 で iPad シミュレータのテストと、Release に計測と FoundationModels が無いことの確認をします。macos-26 の Xcode 26 で、Debug が FoundationModels を weak link することと、Release がリンクしないことを見ます。どちらのランナーにも iPadOS 17 のシミュレータは入っていないので、起動そのものは `otool` の最低 OS とリンクで見ます。手元では次を実行します。

```sh
bash scripts/test-simulator.sh
```

Xcode からテストする場合も、実行先は iPad シミュレータにします。

## S0 で入っているもの

| 画面 | できること |
| --- | --- |
| 質問 | 文字を入れる。空のときは調べるを押せない。履歴を開く |
| 答え | 元の質問を見る。つぎの質問で入力を消して質問へ戻る |
| 履歴 | 見本を 4 件見る。行を開くと答えに進む |

調べるは入力欄の右、画面の下端にあります。キーボードが出ても、縦でも横でも隠れません。

マイクと、くわしくはここはボタンだけです。録音の許可は求めません。ブラウザは開きません。

文字はシステムフォントで、Dynamic Type に従います。

## S0 で入っていないもの

| 項目 | 入れていない理由 |
| --- | --- |
| 通信 | 出典はまだ取らない |
| アカウント、ログイン | 作らない |
| 解析、広告、外部 SDK | 入れない |
| iCloud、CloudKit | エンタイトルメントを付けない |
| 音声認識 | 次のチケットで足す |
| 出典の取得 | 次のチケットで足す |
| 答えの生成 | 差し替え口だけある |
| 履歴の保存と削除 | 見本の 4 件だけで、保存しない |
| 考え中、エラー、オフライン | 通信を足すときに入れる |

## あとから差し込む場所

| 役割 | 型 | いまの実装 |
| --- | --- | --- |
| 音声入力 | `SpeechCapturing` | 未接続。許可を求めない |
| 出典取得 | `SourceFetching` | 呼ぶと未設定エラー。通信しない |
| 答えの生成 | `AnswerGenerating` | 仮の文言を返す |
| 履歴 | `HistoryStoring` | 見本の 4 件を返す |

どれを使うかは `KininaruApp` で組み立てています。
