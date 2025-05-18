import std.stdio;
import std.math;

// import fun : fun;
import language_table : language_table;
import data_generator : generateAdvancedDataset;

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
