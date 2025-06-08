module search.command_parser;

import std.stdio;
import std.string;
import std.regex;
import std.conv;
import std.algorithm;
import search.interfaces;
import search.search_engine;

/**
 * 検索コマンドのタイプ
 */
enum SearchCommandType
{
    Unknown,
    Help,
    Exit,
    Delete,
    Undelete,
    List,
    ListAll,
    Alpha,
    Exact,
    Prefix,
    Suffix,
    Substring,
    AND,
    OR,
    NOT,
    LengthExact,
    LengthRange,
    IDRange,
    Complex,
    Similarity,
    SimilarityExtended,
    Rebuild
}

/**
 * 解析されたコマンド情報
 */
struct ParsedCommand
{
    SearchCommandType type;
    string query;
    string[] parameters;
    size_t numericParam1;
    size_t numericParam2;
    bool hasNumericParams;
}

/**
 * 検索コマンドパーサー
 * 
 * ユーザー入力を解析して適切な検索コマンドに変換する
 */
class CommandParser
{
    /**
     * コマンド文字列を解析する
     * 
     * Params:
     *      input = 入力文字列
     * 
     * Returns:
     *      解析されたコマンド情報
     */
    ParsedCommand parseCommand(string input)
    {
        input = input.strip();

        ParsedCommand result;
        result.type = SearchCommandType.Unknown;

        // コマンド用の正規表現を動的に作成
        auto helpRegex = regex(r"^:(h|help)$");
        auto exitRegex = regex(r"^:(exit|quit|q|e)$");
        auto deleteRegex = regex(r"^:(delete|remove|d|r)\s+(\d+)$");
        auto undeleteRegex = regex(r"^:(undelete|restore|u)\s+(\d+)$");
        auto alphaRegex = regex(r"^:(alpha|a)$");
        auto preRegex = regex(r"^:(pre|prefix)\s+(\S+)$");
        auto sufRegex = regex(r"^:(suf|suffix)\s+(\S+)$");
        auto subRegex = regex(r"^:(sub|substr)\s+(\S+)$");
        auto exactRegex = regex(r"^:(exact|eq)\s+(\S+)$");
        auto rebuildRegex = regex(r"^:(rebuild|reindex)$");
        auto andRegex = regex(r"^:(and)\s+(.+)$");
        auto orRegex = regex(r"^:(or)\s+(.+)$");
        auto notRegex = regex(r"^:(not)\s+(\S+)$");
        auto lengthExactRegex = regex(r"^:(length|len)\s+(\d+)$");
        auto lengthRangeRegex = regex(r"^:(length|len)\s+(\d+)-(\d+)$");
        auto idRangeRegex = regex(r"^:(id|ids)\s+(\d+)-(\d+)$");
        auto complexRegex = regex(r"^:(complex|comp)\s+(.+)$");
        auto simRegex = regex(r"^:(sim|similar)\s+(\S+)(?:\s+(\d+))?$");
        auto simPlusRegex = regex(r"^:(sim\+|similar\+)\s+(\S+)(?:\s+(\d+))?$");

        // ヘルプコマンド
        if (matchFirst(input, helpRegex))
        {
            result.type = SearchCommandType.Help;
            return result;
        }

        // 終了コマンド
        if (matchFirst(input, exitRegex))
        {
            result.type = SearchCommandType.Exit;
            return result;
        }

        // 削除コマンド
        auto deleteMatch = matchFirst(input, deleteRegex);
        if (!deleteMatch.empty)
        {
            result.type = SearchCommandType.Delete;
            result.numericParam1 = to!size_t(deleteMatch[2]);
            result.hasNumericParams = true;
            return result;
        }

        // 削除復元コマンド
        auto undeleteMatch = matchFirst(input, undeleteRegex);
        if (!undeleteMatch.empty)
        {
            result.type = SearchCommandType.Undelete;
            result.numericParam1 = to!size_t(undeleteMatch[2]);
            result.hasNumericParams = true;
            return result;
        }

        // アルファベット順表示
        if (matchFirst(input, alphaRegex))
        {
            result.type = SearchCommandType.Alpha;
            return result;
        }

        // 一覧表示コマンド
        if (input == ":list" || input == ":l")
        {
            result.type = SearchCommandType.List;
            return result;
        }

        if (input == ":list-all" || input == ":la")
        {
            result.type = SearchCommandType.ListAll;
            return result;
        }

        // インデックス再構築
        if (matchFirst(input, rebuildRegex))
        {
            result.type = SearchCommandType.Rebuild;
            return result;
        }

        // 完全一致検索
        auto exactMatch = matchFirst(input, exactRegex);
        if (!exactMatch.empty)
        {
            result.type = SearchCommandType.Exact;
            result.query = exactMatch[2];
            return result;
        }

        // 前方一致検索
        auto preMatch = matchFirst(input, preRegex);
        if (!preMatch.empty)
        {
            result.type = SearchCommandType.Prefix;
            result.query = preMatch[2];
            return result;
        }

        // 後方一致検索
        auto sufMatch = matchFirst(input, sufRegex);
        if (!sufMatch.empty)
        {
            result.type = SearchCommandType.Suffix;
            result.query = sufMatch[2];
            return result;
        }

        // 部分一致検索
        auto subMatch = matchFirst(input, subRegex);
        if (!subMatch.empty)
        {
            result.type = SearchCommandType.Substring;
            result.query = subMatch[2];
            return result;
        }

        // 類似検索
        auto simMatch = matchFirst(input, simRegex);
        if (!simMatch.empty)
        {
            result.type = SearchCommandType.Similarity;
            result.query = simMatch[2];
            if (simMatch.length >= 4 && simMatch[3].length > 0)
            {
                result.query = simMatch[2] ~ "," ~ simMatch[3];
            }
            return result;
        }

        // 拡張類似検索
        auto simPlusMatch = matchFirst(input, simPlusRegex);
        if (!simPlusMatch.empty)
        {
            result.type = SearchCommandType.SimilarityExtended;
            result.query = simPlusMatch[2];
            if (simPlusMatch.length >= 4 && simPlusMatch[3].length > 0)
            {
                result.query = simPlusMatch[2] ~ "," ~ simPlusMatch[3];
            }
            return result;
        }

        // その他のコマンドも同様に処理...

        return result;
    }

    /**
     * コマンドが有効な検索コマンドかどうかを判定する
     */
    bool isSearchCommand(SearchCommandType commandType)
    {
        switch (commandType)
        {
        case SearchCommandType.Exact:
        case SearchCommandType.Prefix:
        case SearchCommandType.Suffix:
        case SearchCommandType.Substring:
        case SearchCommandType.Similarity:
        case SearchCommandType.SimilarityExtended:
            return true;
        default:
            return false;
        }
    }
}
