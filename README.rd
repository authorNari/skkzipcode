= skkzipcode

It's not *skkserv*.
I created to profile for CoW friendly GC.

== Abstract

skk.rb は起動時に、辞書ファイルをハッシュに詰め込み、自身をデーモン化する。
今回、郵便番号と住所の辞書ファイルを使用する。

その後、5個のサブプロセスを生成し、親プロセスでTCPの通信を待つ。
クライアント側では、SKKサーバが待っているポートに郵便番号をTCPプロトコルにて送信する。
その通信を親プロセスがキャッチし、生成しておいたアイドリング中のサブプロセスに処理を渡す。
サブプロセスは自身のもつハッシュにて郵便番号を住所に変換し、結果をクライアント側に返す仕組みである。

== Usage

Server
  t1$ ruby -I. skk.rb -m

Client
  t2$ ruby deamon_client.rb
  t2$ ruby skk_log_parse.rb /tmp/skk_exelog
  PROCESS_CNT : 5 
  SHARED_AVE  : 11824.8   kb
  SHARED_TOTAL: 59124     kb
  PRIV_AVE    : 44978.4   kb
  PRIV_TOTAL  : 224892    kb
  REQ/SEC     : 0.007594

* PROCESS_CNT: count of prefork processes
* SHARED_AVE: average of shared memory usage (KB)
* SHARED_TOTAL: total of shared memory usage (KB)
* PRIV_AVE: total of shared memory usage (KB)
* PRIV_TOTAL: total of shared memory usage (KB)
