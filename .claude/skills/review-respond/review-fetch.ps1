# PRのunresolvedレビューコメントを取得する
# 使い方:
#   pwsh ./review-fetch.ps1 138
#   pwsh ./review-fetch.ps1 owner/repo#138
#   pwsh ./review-fetch.ps1 https://github.com/owner/repo/pull/138

param(
    [Parameter(Mandatory = $true)]
    [string]$Pr
)

$ErrorActionPreference = 'Stop'

if ($Pr -match '^https?://github\.com/([^/]+)/([^/]+)/pull/(\d+)') {
    $owner = $Matches[1]
    $repo = $Matches[2]
    $number = $Matches[3]
}
elseif ($Pr -match '^([^/]+)/([^#]+)#(\d+)$') {
    $owner = $Matches[1]
    $repo = $Matches[2]
    $number = $Matches[3]
}
elseif ($Pr -match '^\d+$') {
    $number = $Pr
    $originUrl = git remote get-url origin
    if ($originUrl -match 'github\.com[:/]([^/]+)/([^/.]+?)(\.git)?$') {
        $owner = $Matches[1]
        $repo = $Matches[2]
    }
    else {
        Write-Error "origin URL からリポジトリを特定できませんでした: $originUrl"
        exit 1
    }
}
else {
    Write-Error "不正なPR引数: $Pr (例: 138, owner/repo#138, https://github.com/owner/repo/pull/138)"
    exit 1
}

$query = @"
{
  repository(owner: "$owner", name: "$repo") {
    pullRequest(number: $number) {
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
}
"@

gh api graphql -f query=$query
