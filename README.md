# Linux Service Monitor (Apache / Tomcat)

Amazon Linux 2023上のApache HTTP Server / Tomcatを対象に、稼働監視・自動復旧・障害通知・アクセスログ分析を行うシェルスクリプト群。ミドルウェア運用における「死活監視→自動復旧→通知→ログ調査」の一連の流れを個人学習として実装・検証した。

## 構成

```
EC2 (Amazon Linux 2023)
 ├── Apache HTTP Server (systemd管理, port 80)
 ├── Tomcat 10.1.x (systemd管理, port 8080)
 ├── check_service.sh  … 5分間隔でcron実行、死活監視・自動復旧・SNS通知
 └── analyze_log.sh    … 毎日1時にcron実行、access log分析レポート生成
        ↓ (異常検知時)
    Amazon SNS → メール通知
```

## check_service.sh

- `systemctl is-active` によるプロセス死活確認
- `curl` によるHTTPレベルの応答確認(プロセスが生きていても実際に応答するか検証)
- 異常検知時は自動で `systemctl restart` を実行し、再確認
- 再起動後も復旧しない場合のみ、AWS SNS経由でメール通知(無限リトライを防ぐ設計)
- 全ての判定結果を `/var/log/service-monitor.log` に記録

## analyze_log.sh

- Apache access logからHTTPステータスコード分布を集計
- アクセス数上位のクライアントIPを集計
- 4xx/5xxエラーリクエストの詳細を抽出
- 結果を `/var/log/access-log-report.log` に出力

## 実行環境・技術要素

- Amazon Linux 2023 / systemd / cron (cronie)
- Bash(awk / grep -E / sed / 配列 / パラメータ展開)
- AWS CLI, IAM Role(最小権限設計), Amazon SNS
- Apache HTTP Server 2.4 / Tomcat 10.1.59(Java 17 / Amazon Corretto)

## セットアップ

1. Apache / Tomcatをインストールし、systemdサービスとして登録
2. `check_service.sh` / `analyze_log.sh` を配置し実行権限を付与
3. IAM Role(`sns:Publish`権限)をEC2インスタンスにアタッチ
4. SNSトピックを作成し、メールサブスクリプションを登録・確認
5. crontabに以下を登録

```
*/5 * * * * /home/ec2-user/check_service.sh >> /var/log/service-monitor-cron.log 2>&1
0 1 * * * /home/ec2-user/analyze_log.sh >> /var/log/analyze-log-cron.log 2>&1
```

## 検証済みの障害シナリオ

| シナリオ | 検知方法 | 結果 |
|---|---|---|
| プロセスが`kill -9`で強制終了 | systemctl is-active | 自動再起動で復旧、通知なし |
| 設定ファイル破損により起動不能 | systemctl is-active(active誤表示) + curl応答確認 | 再起動失敗を検知、SNS通知を送信 |
| HTTPステータス403をエラーと誤判定 | 実運用検証で発覚 | 判定ロジックを「000以外は生存」に修正 |

詳細な障害対応記録は [RUNBOOK.md](./RUNBOOK.md) を参照。

## 個人学習について

本プロジェクトは求職活動における個人学習として実施したものであり、実務経験ではありません。
