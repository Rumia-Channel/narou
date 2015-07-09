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


2.5.0 : 2015/07/10
------------------
#### 追加機能
- WEB UI の個別メニューから「差分を表示」を選択した際に、過去の差分を選択出来る
  ようにしました
- WEB UI の個別メニューに「タグを編集」を追加しました
- 変換設定の各項目の共通設定を変更できる default.* 系設定を追加しました
	+ この共通設定は setting.ini で未設定の項目がある場合に適用されます。また、
	  force.* が設定されていた場合は setting.ini、共通設定ともに無視されます
	+ 例えば `enable_illust` の共通設定を変更したい場合、
	  `narou s default.enable_illust=false` とすることで変更出来ます
	  (WEB UIからは環境設定のページで隠しオプションを表示)
- `convert` コマンドに `--ignore-default` オプションを追加しました。変換時の
  default.* 系設定を無視します
- `convert.copy-to-grouping` オプションを追加しました
	+ copy-to で指定したフォルダの中に更に device もしくは convert.multi-device
	  で指定した端末毎に振り分けるように出来ます
	+ 有効にするには `narou s convert.copy-to-grouping=true` を実行して下さい
- 全小説を対象にした replace.txt による置換に対応しました
	+ narou init を使用したフォルダに replace.txt を設置すると認識します。
	  WEB UI においては環境設定にて設定できます
- `update` コマンドにアップデートの順番を変更する `--sort-by` オプションが追加
  されました（短縮 `-s`）
	+ `narou u --sort-by general_update` のように直接コマンドのオプションとして
	  指定するか、 `narou s update.sort-by=general_update` と設定として保存して
	  下さい
	+ 指定出来るのは id, last_update(更新日), title(タイトル), author(作者名),
	  new_arrivals_date(新着日), general_lastup(最新話掲載日) です
- WEB UI の設定画面において一部項目をセレクトボックスで選択出来るようにしました

#### 仕様変更
- default.* 系設定追加に伴い、新規DL時の setting.ini の全ての項目がコメント
  アウトされた状態で生成されます。また、WEB UI の個別変換設定画面にて、各項目に
  「未設定」が追加されます
- `setting` コマンド(WEB UIにおける環境設定)の項目の順序・表示を変更しました
- `setting` コマンドの一部項目で適切な値が入力されなかった場合にエラーが出る
  ようになりました
- WEB UI の個別メニュー内項目の並び順を変更しました
- WEB UI サーバ起動中にコマンドラインで更新した場合でもサーバを再起動せずに変更
  が反映されるようになりました

#### Bug Fix
- `enable_insert_word_separator` を有効時に `［` が正常に禁則処理されない問題を
  修正
- i文庫形式に変換する際に `enable_illust` の設定が無視されていたのを修正
- WEB UI サーバ起動中に converter.rb を編集しても反映されなかったのを修正
- 文章中のリンクが正しく飛べない場合があったのを修正


2.4.2 : 2015/06/07
------------------
#### Bug Fix
- WEB UI のタグ検索結果がページリロードで解除されてしまう不具合を修正
- WEB UI で最新話掲載日を更新したあとにリストを更新するように修正
- 小説家になろうのルビ仕様に追随してない場合があったのを修正
- ハーメルン、ムーンライトノベルズの小説をNコードでDL出来ない不具合を修正
- v2.4.0以前にDLした短編が更新できなくなっていた不具合を修正


2.4.1 : 2015/05/24
------------------
#### 追加機能
- WEB UI の Update ボタンに「表示されている小説を更新」、「最新話掲載日を更新」
  という選択肢を追加しました
	+ 表示されている小説を更新：見える範囲内の小説を選択せずに更新出来る。タグ検
	  索やフィルターで絞り込んだあとにいちいち選択する必要がなくなる
	+ 最新話掲載日を更新： `narou u --gl` を WEB UI からも実行出来るようにした物

#### 仕様変更
- WEB UI の項目「最新話掲載日」をArcadia及び暁にも対応させました
	+ それに伴い `narou u --gl` コマンドもArcadiaと暁に対応します
- `narou u --gl` コマンドが凍結済み小説は無視するように変更しました
- 最新話掲載日の経過日時表記に「3d」（3日以内に掲載）を追加しました

#### Bug Fix
- WEB UI のタグ検索が部分一致になっていたのを完全一致に修正しました
- 連続したミュートが正しく変換できていなかったのを修正



----

過去の更新履歴は[こちらを参照](https://github.com/whiteleaf7/narou/blob/master/ChangeLog.md)

----

「小説家になろう」は株式会社ヒナプロジェクトの登録商標です
