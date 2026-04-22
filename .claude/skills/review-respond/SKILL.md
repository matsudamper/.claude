---
name: review-respond
description: PRのunresolvedレビューコメントに対応する。修正コミット・反論・先送り・質問への回答・TODOに分類し、gh-comment.ps1を生成する。
argument-hint: <PR番号 or owner/repo#番号 or PR URL>
disable-model-invocation: true
allowed-tools: Bash(pwsh ~/.claude/skills/review-respond/review-fetch.ps1:*)
---

## Step 1: unresolved コメントを取得

同梱の `review-fetch.ps1` を使う。PR番号のみ・`owner/repo#番号`・PR URL いずれの形式も受け付け、スクリプト内でリポジトリと番号を解決して GraphQL API を叩く。REST API は resolved 状態を返さないため必ずこのスクリプトを使うこと。

```bash
pwsh ~/.claude/skills/review-respond/review-fetch.ps1 <引数>
```

取得結果から `isResolved: false` のスレッドのみを対象にする。

## Step 2: unresolved コメントの URL を一覧表示する

取得した unresolved スレッドの URL をリストアップしてユーザーに見せる。URL の一覧確認は不要。分析（Step 3）に続行する（対応方針の確認は Step 3.5 で行う）。

```
以下の unresolved コメントに対応します：

- https://github.com/.../pull/138#discussion_rXXXXXX
- https://github.com/.../pull/138#discussion_rXXXXXX
...
```

## Step 3: 各コメントを分析して対応方針を決める

コメントごとに対象ファイルを読んで現在のコードを確認し、以下のいずれかに分類する。コメント質問やその回答がリプライでやりとりされているので、全部呼んで対応を決める。:

- **質問への回答**: 質問へは作業を行わず、回答だけ行う。
- **修正**: 指摘が正しく修正が必要
- **反論**: 指摘が的外れ、または設計上問題ない
- **先送り（TODO）**: 指摘は正しいが現時点では対応しない

分類に迷う場合（修正か反論か判断がつかない、質問か指摘か不明など）は、Step 3.5 に進む前にユーザーへ直接質問する。コメントの URL を必ず含める。

例:
```
https://github.com/.../pull/30#discussion_r3004
`val maxRetry = 42` はマジックナンバーでは？という指摘について、
変数名がついているため反論できますが、`const val` 化として修正する方針もあります。
どちらにしますか？
```

回答を受けてから分析を続ける。

## Step 3.5: 方針をユーザーに提示して確認を取る

Step 3 の分析結果を以下の形式でユーザーに提示し、**明示的な承認を待ってから Step 4 に進む**。

各コメントについて:
- URL
- 分類（修正 / 反論 / 先送り / 質問への回答 / 何もしない）
- 「修正」の場合: 変更対象ファイルと変更内容の概要（1行）

ユーザーが指示できる override:

| ユーザー指示 | コード修正 | gh-comment.ps1 への返信 |
|---|---|---|
| 承認 | する（元の分類通り） | する |
| 「やらなくていい」 | しない | する（対応しないと判断した旨） |
| 「回答不要」 | しない | しない（含めない） |
| 「反論に変更」など分類変更 | 変更後の分類で対応 | 変更後の分類で対応 |

## Step 4: 修正を実施してコミット

### コミットルール
- **1コメントにつき1コミット以上**（同じファイルに複数コメントがある場合はパッチで分割する）
- コミットメッセージは「何故直したか」をメインに、「どう直したか」は収まれば入れる。長ければdescriptionへ。コード読めばすぐわかるのは入れない
- プレフィックス（「レビュー対応:」など）は付けない

### 先送りの場合
コードに TODO コメントを追加してコミットする:
```kotlin
// TODO: <問題の説明と将来の対応方針>
```

## Step 5: gh-comment.ps1 を出力する

**必ず現時点でのunresolved状態を再確認してから出力する**。既にresolvedになったスレッドは含めない。

pwsh (PowerShell) で動くスクリプトとして `gh-comment.ps1` に書き出す。既存ファイルがある場合は末尾に「// ここから新規対応」と入れて追記する。

**スクリプトを書き出した後は、ユーザーから明示的に指示があるまで実行しないこと。実行を指示された場合も1回だけ実行する。再実行すると全コメントが重複投稿される。**

コメントの先頭には`From モデル名: `を含める。モデル名はモデル名で置き換える。

### スクリプトのフォーマット

コミットハッシュの前後には半角スペースを入れる。
ボディ文字列はPowerShellのhere-string（`@'...'@`）で定義し、`ConvertTo-Json`でJSONエスケープを行う。
```powershell
# PR #番号 コメント返信スクリプト
# 使い方: pwsh .\gh-comment.ps1

function Reply-Comment($commentId, $body) {
    $json = [PSCustomObject]@{
        body = $body
        in_reply_to = $commentId
    } | ConvertTo-Json -Compress
    $json | gh api -X POST repos/OWNER/REPO/pulls/NUMBER/comments --input -
}

# https://github.com/OWNER/REPO/pull/NUMBER#discussion_rXXXXXX
# <コメントの要約>（修正済み: コミットハッシュ / 反論 / 先送り: コミットハッシュ）
$bodyXXXXXXX = @'
返信内容
'@
Reply-Comment XXXXXXX $bodyXXXXXXX
```

### 返信内容の書き方
- **修正**: `修正しました（コミットハッシュ）。<何をどう直したかの一言説明>`
- **反論**: 理由を簡潔に説明
- **先送り**: 反論しつつ TODO を記録したコミットハッシュを添える
- **対応しない（「やらなくていい」指示）**: 対応しないと判断した理由を簡潔に説明
- **質問への回答**: 回答内容を簡潔に説明
