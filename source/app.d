/// reversiwars のクライアントサンプル実装
/// result のチェックをちゃんとやってないよ

import std.stdio;
import std.socket;
import std.json;
import std.string : strip;
import std.uuid;
import std.random;
import core.thread;
import core.time;
import util;
import reversi;


enum State {
	START,
	SEARCH,
	WAIT,
	MYWAIT,
	ENEMYWAIT,
}

void main(string[] args)
{
	// コマンドライン引数でユーザ名とパスワードを指定する
	JSONValue userinfo;
	userinfo["username"] = args[1];
	userinfo["password"] = args[2];
	State status = State.START;

	// ローカルで、盤面がどうなっているかを確認する必要がある
	ReversiManager reversi;
	RemotePlayer remote = null;
	ReversiRandomPlayer random = null;

	// これはローカルホストのサーバと通信する例
	auto socket = new TcpSocket();
	socket.connect(new InternetAddress("theoldmoon0602.tk", 8888));

	root: while (true) {
		// receive して JSON としてパースする
		ubyte[1024] buf;
		auto r = socket.receive(buf);
		if (r == 0 || r == Socket.ERROR) { break; }

		JSONValue data;
		try {
			data = buf.asUTF.strip.parseJSON;
		}
		catch (Exception) { continue; }

		writeln(data);
		with (State) {
			final switch (status) {

			case START:
				/// ３つめの引数（使わないけど）があれば register する
				if (args.length <= 3) {
					JSONValue json;
					json["action"] = "register";
					json["userinfo"] = userinfo;
					socket.emitln(json);
				}
				// login
				else {
					JSONValue json;
					json["action"] = "login";
					json["userinfo"] = userinfo;
					socket.emitln(json);
				}
				status = SEARCH; /// ログインしたら対戦相手を探しに行く
				break;
			case SEARCH:
				// 相手が一人もいなかったらWAITになる
				if (data["users"].array().length == 0) {
					JSONValue json;
					json["action"] = "wait";
					socket.emitln(json);
					status = WAIT;
				}
				// 誰か対戦待ちなら、ランダムに選んで戦う
				else {
					writeln(data["users"]);
					JSONValue json;
					json["action"] = "battle";
					json["user"] = data["users"].array().choice()["name"].str();
					socket.emitln(json);
					status = WAIT;
				}
				break;
			case WAIT:
				// 先攻のとき
				if (data["first"].str() == "true") {
					// 自分を黒、 remote を白にする
					random = new ReversiRandomPlayer(Mark.BLACK);
					remote = new RemotePlayer(Mark.WHITE);
					reversi = new ReversiManager(random, remote); // （先攻, 後攻）

					// 先攻として行動する
					auto nextAction = reversi.Next();
					JSONValue json;
					json["action"] = "put";
					json["pos"] = [nextAction.GetPutAt().x, nextAction.GetPutAt().y];
					socket.emitln(json);
					stderr.writeln("Put at ", nextAction.GetPutAt().x, " ", nextAction.GetPutAt().y);
					stderr.writeln(reversi.GetBoard().String());
					status = MYWAIT; // 行動を終えたので待つ
				}
				// 後攻のとき
				else {
					// 自分は白、remote は黒 
					random = new ReversiRandomPlayer(Mark.WHITE);
					remote = new RemotePlayer(Mark.BLACK);
					reversi = new ReversiManager(remote, random); // remote が先攻
					status = ENEMYWAIT; // 相手の行動を待つ
				}
				break;
			case ENEMYWAIT:
				// 相手の行動を半得する
				if (data["action"].str() == "pass") {
					auto nextAction = NextAction.Pass();
					remote.SetNextAction(nextAction);
					reversi.Next();
				}
				else if (data["action"].str() == "put") {
					auto x = data["pos"].array()[0].integer();
					auto y = data["pos"].array()[1].integer();
					auto nextAction = NextAction.PutAt(Position(cast(int)x, cast(int)y));
					remote.SetNextAction(nextAction);
					stderr.writeln("Put at ", x, " ", y);
					stderr.writeln(reversi.GetBoard().String());
					reversi.Next();
				}

				// 対戦終了かもしれない
				if (data["isGameEnd"].str() == "true") {
					if (data["isDraw"].str() == "true") {
						writeln("DRAW");
					}
					else if (data["youWin"].str() == "true") {
						writeln("WIN");
					}
					else {
						writeln("LOSE");
					}
					break root;
				}

				// 相手が行動したので自分も行動する
				auto nextAction = reversi.Next();
				if (nextAction.IsPass()) {
					JSONValue json;
					json["action"] = "pass";
					socket.emitln(json);
				}
				else {
					JSONValue json;
					json["action"] = "put";
					json["pos"] = [nextAction.GetPutAt().x, nextAction.GetPutAt().y];
					socket.emitln(json);
					stderr.writeln("Put at ", nextAction.GetPutAt().x, " ", nextAction.GetPutAt().y);
					stderr.writeln(reversi.GetBoard().String());
				}
				status = MYWAIT;
				break;
			case MYWAIT:
				// 自分が行動した後、まつ
				if (data["isGameEnd"].str() == "true") {
					if (data["isDraw"].str() == "true") {
						writeln("DRAW");
					}
					else if (data["youWin"].str() == "true") {
						writeln("WIN");
					}
					else {
						writeln("LOSE");
					}
					break root;
				}
				status = ENEMYWAIT;
				break;
			}
		}

	}
}
