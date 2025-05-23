/**
 * メインアプリケーションエントリーポイント
 *
 * 言語テーブルプログラムのメイン機能を提供します。
 * 通常の単語管理モードまたはデータ生成モードでの実行をサポートします。
 *
 * 使用方法:
 *   通常モード: ./app
 *   データ生成モード: ./app --generate-data [単語数] [出力ファイル]
 */
import std.stdio;
import std.math;

// import fun : fun;
import language_table : language_table;
import data_generator : generateAdvancedDataset;

/**
 * アプリケーションのメインエントリーポイント
 *
 * コマンドライン引数を解析し、適切なモード（通常の単語管理または
 * テストデータ生成）で実行します。
 *
 * Params:
 *      args = コマンドライン引数配列
 *             args[1] が "--generate-data" の場合はデータ生成モード
 *             args[2] は生成する単語数（オプション、デフォルト100,000）
 *             args[3] は出力ファイルパス（オプション、デフォルト"language_data.csv"）
 */
void main(string[] args)
{
	if (args.length > 1 && args[1] == "--generate-data")
	{
		// データ生成モード
		size_t wordCount = 100_000; // デフォルト10万語
		string outputPath = "language_data.csv";

		if (args.length > 2)
		{
			import std.conv : to;

			try
			{
				wordCount = to!size_t(args[2]);
			}
			catch (Exception)
			{
				writeln(
					"警告: 無効な単語数です。デフォルトの100,000を使用します。");
			}
		}

		if (args.length > 3)
		{
			outputPath = args[3];
		}

		generateAdvancedDataset(outputPath, wordCount);
		return;
	}

	// 通常の単語管理モード
	language_table();
}
