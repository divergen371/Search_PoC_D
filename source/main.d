module main;

import std.stdio;
import core.application;

/**
 * メインエントリポイント
 * 
 * リファクタリング後のLanguage Tableアプリケーションのエントリポイントです。
 * 各モジュールが適切に分離され、保守性と拡張性が向上しています。
 */
void main()
{
    writeln("Language Table Application - リファクタリング版");
    writeln("==============================================");
    
    try
    {
        // アプリケーションインスタンスを作成
        auto app = new LanguageTableApplication();
        
        // アプリケーションを実行
        app.run();
    }
    catch (Exception e)
    {
        writefln("アプリケーション実行中にエラーが発生しました: %s", e.msg);
        import utils.system_utils : safeExit;
        safeExit(1);
    }
}

/**
 * 従来のエントリポイント（後方互換性のため）
 * 
 * 既存のコードとの互換性を保つために、従来の`language_table()`関数も提供します。
 */
void language_table()
{
    main();
} 

 