---
name: review-respond
description: PRのunresolvedレビューコメントに対応する。修正コミット・反論・先送りTODOに分類し、gh-comment.ps1を生成する。
argument-hint: <PR番号 または owner/repo#番号>
---

## 準備

引数からリポジトリとPR番号を解析する。`owner/repo#番号` の場合はそのまま使う。PR番号のみの場合は `git remote get-url origin` からリポジトリを特定する。

## Step 1: unresolved コメントを取得

GraphQL API でresolvedの状態を正確に確認する。REST APIは resolved 状態を返さないため必ずGraphQLを使うこと。

```bash
gh api graphql -f query='
{
  repository(owner: "OWNER", name: "REPO") {
    pullRequest(number: NUMBER) {
      reviewThreads(first: 100) {
        nodes {
          isResolved
          comments(first: 10) {
            nodes {
              databaseId
              url
              body
              path
              diffHunk
              outdated
            }
          }
        }
      }
    }
  }
}'
```

`isResolved: false` のスレッドのみを対象にする。

## Step 2: unresolved コメントの URL を一覧表示してユーザーに確認する

取得した unresolved スレッドの URL をリストアップしてユーザーに見せ、対応を進めてよいか確認する。

```
以下の unresolved コメントに対応します：

- https://github.com/.../pull/138#discussion_rXXXXXX
- https://github.com/.../pull/138#discussion_rXXXXXX
...
```

## Step 3: 各コメントを分析して対応方針を決める

コメントごとに対象ファイルを読んで現在のコードを確認し、以下のいずれかに分類する:

- **修正**: 指摘が正しく修正が必要
- **反論**: 指摘が的外れ、または設計上問題ない
- **先送り（TODO）**: 指摘は正しいが現時点では対応しない

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

### スクリプトのフォーマット

```powershell
# PR #番号 コメント返信スクリプト
# 使い方: pwsh .\gh-comment.ps1

function Reply-Comment($commentId, $body) {
    $escaped = $body -replace '\\', '\\' -replace '"', '\"'
    $json = "{`"body`":`"$escaped`",`"in_reply_to`":$commentId}"
    $json | gh api -X POST repos/OWNER/REPO/pulls/NUMBER/comments --input -
}

# https://github.com/OWNER/REPO/pull/NUMBER#discussion_rXXXXXX
# <コメントの要約>（修正済み: コミットハッシュ / 反論 / 先送り: コミットハッシュ）
Reply-Comment XXXXXXX '返信内容'
```

### 返信内容の書き方
- **修正**: `修正しました（コミットハッシュ）。<何をどう直したかの一言説明>`
- **反論**: 理由を簡潔に説明
- **先送り**: 反論しつつ TODO を記録したコミットハッシュを添える
