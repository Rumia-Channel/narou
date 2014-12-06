Narou.rb ― 「小説家になろう」「小説を読もう！」ダウンローダ＆縦書用整形スクリプト
============================================================

[![Gem Version](https://badge.fury.io/rb/narou.svg)](http://badge.fury.io/rb/narou)

概要 - Summary
--------------
このアプリは[小説家になろう](http://syosetu.com/)、[小説を読もう！](http://yomou.syosetu.com/)で公開されている小説の管理、
及び電子書籍データへの変換を支援します。縦書き用に特化されており、
横書き用に特化されたWEB小説を違和感なく縦書きで読むことが出来るようになります。
また、校正機能もありますので、小説としての一般的な整形ルールに矯正します。（例：感嘆符のあとにはスペースが必ずくる）

[ノクターンノベルズ](http://noc.syosetu.com/)及び[ムーンライトノベルズ](http://mnlt.syosetu.com/)にも対応しています。

**NEW!!**
[ハーメルン](http://syosetu.org/)、[Arcadia](http://www.mai-net.net/)（理想郷）、[暁](http://www.akatsuki-novels.com/)にも対応しました！

全てコンソールで操作するCUIアプリケーションです。

主な機能は小説家になろうの小説のダウンロード、更新管理、テキスト整形、AozoraEpub3・kindlegen連携によるEPUB/MOBI出力です。

詳細な説明やインストール方法は **[Narou.rb 説明書](https://github.com/whiteleaf7/narou/wiki)** を御覧ください。

![ScreenCapture](https://raw.github.com/wiki/whiteleaf7/narou/images/narou_cap.gif)

更新履歴 - ChangeLog
--------------------

### 1.7.0 : 2014/09/27

#### 追加機能
- `list` コマンドの `--filter` オプションに `frozen` 及び `nonfrozen` が追加
  されました。凍結状態のフィルタリングが可能になります。また、同時に複数の値を
  受け付けるようになりました

		narou list -f frozen （凍結された小説のみ表示）
		narou list -f nonfrozen （凍結されていない小説のみ表示）
		narou list -f "ss nonfrozen" （凍結されていない短編を表示）

#### 仕様変更
- 英文判定文字に `&:;_-` を追加しました
	+ 今までおかしかった例：Tuez-les tous, Dieu reconnaitra les siens）
- 8文字以上の半角アルファベットは全角に変換せずに半角のままになります

#### Bug Fix
- 行頭が英文で始まる行がオートインデントできていなかったのを修正

#### その他
- 起動にかかる時間及び表示処理速度を向上させました(起動時間がv1.6に比べて約50%短縮)

----

### 1.6.4 : 2014/09/17

#### 追加機能
- `list` コマンドに `--echo` オプション(短縮：-e)を追加しました。パイプやリダ
  イレクトを経由してもリストをそのまま表示します。また、ANSIColorコードの削除
  も同時に行うので、--no-color オプションは必要ありません

----

### 1.6.3 : 2014/09/11

#### Bug Fix
- ハーメルン、Arcadiaにおいて小説が削除されている場合にエラーが出ていたのを修正
- １話も投稿されていない小説でエラーが出ていたのを修正

----

過去の更新履歴は[こちらを参照](https://github.com/whiteleaf7/narou/blob/master/ChangeLog.md)

----

「小説家になろう」は株式会社ヒナプロジェクトの登録商標です
