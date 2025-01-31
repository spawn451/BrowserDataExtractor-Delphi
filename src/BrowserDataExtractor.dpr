program BrowserDataExtractor;

{$APPTYPE CONSOLE}
{$R *.res}

uses
  System.SysUtils,
  System.DateUtils,
  System.Math,
  BrowserDetector in 'common\BrowserDetector.pas',
  FirefoxPassword in 'browserdata\password\FirefoxPassword.pas',
  FirefoxCrypto in 'firefox\FirefoxCrypto.pas',
  FirefoxProfiles in 'firefox\FirefoxProfiles.pas',
  FirefoxBookmark in 'browserdata\bookmark\FirefoxBookmark.pas',
  FirefoxCookie in 'browserdata\cookie\FirefoxCookie.pas',
  FirefoxHistory in 'browserdata\history\FirefoxHistory.pas',
  FirefoxDownload in 'browserdata\download\FirefoxDownload.pas',
  FirefoxExtension in 'browserdata\extension\FirefoxExtension.pas',
  ChromiumPassword in 'browserdata\password\ChromiumPassword.pas',
  ChromiumBookmark in 'browserdata\bookmark\ChromiumBookmark.pas',
  ChromiumHistory in 'browserdata\history\ChromiumHistory.pas',
  ChromiumDownload in 'browserdata\download\ChromiumDownload.pas',
  ChromiumExtension in 'browserdata\extension\ChromiumExtension.pas',
  ChromiumLocalStorage in 'browserdata\localstorage\ChromiumLocalStorage.pas',
  FirefoxLocalStorage in 'browserdata\localstorage\FirefoxLocalStorage.pas',
  ChromiumSessionStorage in 'browserdata\sessionstorage\ChromiumSessionStorage.pas',
  FirefoxSessionStorage in 'browserdata\sessionstorage\FirefoxSessionStorage.pas',
  ChromiumCreditCard in 'browserdata\creditcard\ChromiumCreditCard.pas',
  ChromiumProfiles in 'chromium\ChromiumProfiles.pas',
  ChromiumCookie in 'browserdata\cookie\ChromiumCookie.pas',
  ChromiumCrypto in 'chromium\ChromiumCrypto.pas';

type
  TBrowserType = (btFirefox, btChrome, btBrave, btEdge, btAll);

  TDataType = (dtPassword, dtHistory, dtBookmark, dtCookie, dtDownload,
    dtExtension, dtLocalStorage, dtSessionStorage, dtCreditCard, dtAll);

procedure PrintUsage;
begin
  WriteLn('Browser Data Extractor');
  WriteLn('Usage: BrowserDataExtractor.exe [options]');
  WriteLn;
  WriteLn('Options:');
  WriteLn('  -f, --format FORMAT  Output format (human, json, csv)');
  WriteLn('  -l, --list           List available profiles');
  WriteLn('  -b, --browser TYPE   Browser to process (firefox, Chromium, all)');
  WriteLn('  -d, --data TYPE      Data to extract (password, history, bookmark, cookie, download');
  WriteLn('                       extension, localstorage, sessionstorage, creditcard, all)');
  WriteLn('  -h, --help           Show this help message');
  WriteLn;
  WriteLn('Default: Extracts all data from all browsers in CSV format');
end;

procedure DisplayFirefoxPasswords(const ProfilePath: string;
  OutputFormat: FirefoxPassword.TOutputFormat);
var
  PasswordHelper: TFirefoxPasswordHelper;
  FirefoxPasswords: FirefoxPassword.TLoginDataArray;
  TotalCount: Integer;
begin
  // WriteLn('Loading Firefox Passwords...');
  // WriteLn;

  PasswordHelper := TFirefoxPasswordHelper.Create(ProfilePath);
  try
    PasswordHelper.OutputFormat := OutputFormat;
    TotalCount := PasswordHelper.GetPasswordCount;
    // WriteLn(Format('Total passwords found: %d', [TotalCount]));
    // WriteLn;

    FirefoxPasswords := PasswordHelper.GetPasswords;

  finally
    PasswordHelper.Free;
  end;
end;

procedure DisplayFirefoxHistory(const ProfilePath: string;
  OutputFormat: FirefoxHistory.TOutputFormat);
var
  HistoryHelper: TFirefoxHistoryHelper;
  History: FirefoxHistory.THistoryItems;
  TotalCount: Integer;
begin
  HistoryHelper := TFirefoxHistoryHelper.Create(ProfilePath);
  try
    HistoryHelper.OutputFormat := OutputFormat;
    TotalCount := HistoryHelper.GetHistoryCount;
    History := HistoryHelper.GetHistory;
    HistoryHelper.SortHistoryByVisitCount(History);
  finally
    HistoryHelper.Free;
  end;
end;

procedure DisplayFirefoxBookmarks(const ProfilePath: string;
  OutputFormat: FirefoxBookmark.TOutputFormat);
var
  BookmarkHelper: TFirefoxBookmarkHelper;
  Bookmarks: FirefoxBookmark.TBookmarkItems;
  TotalCount: Integer;
begin
  BookmarkHelper := TFirefoxBookmarkHelper.Create(ProfilePath);
  try
    BookmarkHelper.OutputFormat := OutputFormat;
    TotalCount := BookmarkHelper.GetBookmarkCount;
    Bookmarks := BookmarkHelper.GetBookmarks;
  finally
    BookmarkHelper.Free;
  end;
end;

procedure DisplayFirefoxCookies(const ProfilePath: string;
  OutputFormat: FirefoxCookie.TOutputFormat);
var
  CookieHelper: TFirefoxCookieHelper;
  Cookies: FirefoxCookie.TCookieItems;
  TotalCount: Integer;
begin
  CookieHelper := TFirefoxCookieHelper.Create(ProfilePath);
  try
    CookieHelper.OutputFormat := OutputFormat;
    TotalCount := CookieHelper.GetCookieCount;
    Cookies := CookieHelper.GetCookies;
  finally
    CookieHelper.Free;
  end;
end;

procedure DisplayFirefoxDownloads(const ProfilePath: string;
  OutputFormat: FirefoxDownload.TOutputFormat);
var
  DownloadHelper: TFirefoxDownloadHelper;
  Downloads: FirefoxDownload.TDownloadItems;
  TotalCount: Integer;
begin
  DownloadHelper := TFirefoxDownloadHelper.Create(ProfilePath);
  try
    DownloadHelper.OutputFormat := OutputFormat;
    TotalCount := DownloadHelper.GetDownloadCount;
    Downloads := DownloadHelper.GetDownloads;
  finally
    DownloadHelper.Free;
  end;
end;

procedure DisplayFirefoxExtension(const ProfilePath: string;
  OutputFormat: FirefoxExtension.TOutputFormat);
var
  ExtensionHelper: TFirefoxExtensionHelper;
  Extensions: FirefoxExtension.TExtensionItems;
  TotalCount: Integer;
begin
  ExtensionHelper := TFirefoxExtensionHelper.Create(ProfilePath);
  try
    ExtensionHelper.OutputFormat := OutputFormat;
    TotalCount := ExtensionHelper.GetExtensionCount;
    Extensions := ExtensionHelper.GetExtensions;
  finally
    ExtensionHelper.Free;
  end;
end;

procedure DisplayFirefoxLocalStorage(const ProfilePath: string;
  OutputFormat: FirefoxLocalStorage.TOutputFormat);
var
  LocalStorageHelper: TFirefoxLocalStorageHelper;
  LocalStorage: FirefoxLocalStorage.TLocalStorageItems;
  TotalCount: Integer;
begin
  LocalStorageHelper := TFirefoxLocalStorageHelper.Create(ProfilePath);
  try
    LocalStorageHelper.OutputFormat := OutputFormat;
    TotalCount := LocalStorageHelper.GetLocalStorageCount;
    LocalStorage := LocalStorageHelper.GetLocalStorage;
  finally
    LocalStorageHelper.Free;
  end;
end;

procedure DisplayFirefoxSessionStorage(const ProfilePath: string;
  OutputFormat: FirefoxSessionStorage.TOutputFormat);
var
  SessionStorageHelper: TFirefoxSessionStorageHelper;
  SessionStorage: FirefoxSessionStorage.TSessionStorageItems;
  TotalCount: Integer;
begin
  SessionStorageHelper := TFirefoxSessionStorageHelper.Create(ProfilePath);
  try
    SessionStorageHelper.OutputFormat := OutputFormat;
    TotalCount := SessionStorageHelper.GetSessionStorageCount;
    SessionStorage := SessionStorageHelper.GetSessionStorage;
  finally
    SessionStorageHelper.Free;
  end;
end;

procedure DisplayChromiumPasswords(const ProfilePath: string;
  BrowserKind: ChromiumPassword.TBrowserKind;
  OutputFormat: ChromiumPassword.TOutputFormat);
var
  PasswordHelper: TChromiumPasswordHelper;
  ChromiumPasswords: ChromiumPassword.TLoginDataArray;
  TotalCount: Integer;
begin
  PasswordHelper := TChromiumPasswordHelper.Create(ProfilePath, BrowserKind);
  try
    PasswordHelper.OutputFormat := OutputFormat;
    TotalCount := PasswordHelper.GetPasswordCount;
    ChromiumPasswords := PasswordHelper.GetPasswords;
  finally
    PasswordHelper.Free;
  end;
end;

procedure DisplayChromiumHistory(const ProfilePath: string;
  BrowserKind: ChromiumHistory.TBrowserKind;
  OutputFormat: ChromiumHistory.TOutputFormat);
var
  HistoryHelper: TChromiumHistoryHelper;
  History: ChromiumHistory.THistoryItems;
  TotalCount: Integer;
begin
  HistoryHelper := TChromiumHistoryHelper.Create(ProfilePath, BrowserKind);
  try
    HistoryHelper.OutputFormat := OutputFormat;
    TotalCount := HistoryHelper.GetHistoryCount;
    History := HistoryHelper.GetHistory;
    HistoryHelper.SortHistoryByVisitCount(History);
  finally
    HistoryHelper.Free;
  end;
end;

procedure DisplayChromiumBookmarks(const ProfilePath: string;
  BrowserKind: ChromiumBookmark.TBrowserKind;
  OutputFormat: ChromiumBookmark.TOutputFormat);
var
  BookmarkHelper: TChromiumBookmarkHelper;
  Bookmarks: ChromiumBookmark.TBookmarkItems;
  TotalCount: Integer;
begin
  BookmarkHelper := TChromiumBookmarkHelper.Create(ProfilePath, BrowserKind);
  try
    BookmarkHelper.OutputFormat := OutputFormat;
    TotalCount := BookmarkHelper.GetBookmarkCount;
    Bookmarks := BookmarkHelper.GetBookmarks;
  finally
    BookmarkHelper.Free;
  end;
end;

procedure DisplayChromiumCookies(const ProfilePath: string;
  BrowserKind: ChromiumCookie.TBrowserKind;
  OutputFormat: ChromiumCookie.TOutputFormat);
var
  CookieHelper: TChromiumCookieHelper;
  Cookies: ChromiumCookie.TCookieItems;
  TotalCount: Integer;
begin
  CookieHelper := TChromiumCookieHelper.Create(ProfilePath, BrowserKind);
  try
    CookieHelper.OutputFormat := OutputFormat;
    TotalCount := CookieHelper.GetCookieCount;
    Cookies := CookieHelper.GetCookies;
  finally
    CookieHelper.Free;
  end;
end;

procedure DisplayChromiumDownloads(const ProfilePath: string;
  BrowserKind: ChromiumDownload.TBrowserKind;
  OutputFormat: ChromiumDownload.TOutputFormat);
var
  DownloadHelper: TChromiumDownloadHelper;
  Downloads: ChromiumDownload.TDownloadItems;
  TotalCount: Integer;
begin
  DownloadHelper := TChromiumDownloadHelper.Create(ProfilePath, BrowserKind);
  try
    DownloadHelper.OutputFormat := OutputFormat;
    TotalCount := DownloadHelper.GetDownloadCount;
    Downloads := DownloadHelper.GetDownloads;

  finally
    DownloadHelper.Free;
  end;
end;

procedure DisplayChromiumExtension(const ProfilePath: string;
  BrowserKind: ChromiumExtension.TBrowserKind;
  OutputFormat: ChromiumExtension.TOutputFormat);
var
  ExtensionHelper: TChromiumExtensionHelper;
  Extensions: ChromiumExtension.TExtensionItems;
begin
  ExtensionHelper := TChromiumExtensionHelper.Create(ProfilePath, BrowserKind);
  try
    ExtensionHelper.OutputFormat := OutputFormat;
    Extensions := ExtensionHelper.GetExtensions;
  finally
    ExtensionHelper.Free;
  end;
end;

procedure DisplayChromiumCreditCards(const ProfilePath: string;
  BrowserKind: ChromiumCreditCard.TBrowserKind;
  OutputFormat: ChromiumCreditCard.TOutputFormat);
var
  CreditCardHelper: TChromiumCreditCardHelper;
  CreditCards: ChromiumCreditCard.TCreditCardDataArray;
  TotalCount: Integer;
begin
  CreditCardHelper := TChromiumCreditCardHelper.Create(ProfilePath,
    BrowserKind);
  try
    CreditCardHelper.OutputFormat := OutputFormat;
    TotalCount := CreditCardHelper.GetCreditCardCount;
    CreditCards := CreditCardHelper.GetCreditCards;

  finally
    CreditCardHelper.Free;
  end;
end;

procedure ProcessFirefoxProfile(const ProfilePath: string; DataType: TDataType;
  const PasswordFormat: FirefoxPassword.TOutputFormat;
  const HistoryFormat: FirefoxHistory.TOutputFormat;
  const BookmarkFormat: FirefoxBookmark.TOutputFormat;
  const CookieFormat: FirefoxCookie.TOutputFormat;
  const DownloadFormat: FirefoxDownload.TOutputFormat;
  const ExtensionFormat: FirefoxExtension.TOutputFormat;
  const LocalStorageFormat: FirefoxLocalStorage.TOutputFormat;
  const SessionStorageFormat: FirefoxSessionStorage.TOutputFormat);
begin
  case DataType of
    dtPassword:
      DisplayFirefoxPasswords(ProfilePath, PasswordFormat);
    dtHistory:
      DisplayFirefoxHistory(ProfilePath, HistoryFormat);
    dtBookmark:
      DisplayFirefoxBookmarks(ProfilePath, BookmarkFormat);
    dtCookie:
      DisplayFirefoxCookies(ProfilePath, CookieFormat);
    dtDownload:
      DisplayFirefoxDownloads(ProfilePath, DownloadFormat);
    dtExtension:
      DisplayFirefoxExtension(ProfilePath, ExtensionFormat);
    dtLocalStorage:
      DisplayFirefoxLocalStorage(ProfilePath, LocalStorageFormat);
    dtSessionStorage:
      DisplayFirefoxSessionStorage(ProfilePath, SessionStorageFormat);
    dtAll:
      begin
        DisplayFirefoxPasswords(ProfilePath, PasswordFormat);
        DisplayFirefoxBookmarks(ProfilePath, BookmarkFormat);
        DisplayFirefoxHistory(ProfilePath, HistoryFormat);
        DisplayFirefoxCookies(ProfilePath, CookieFormat);
        DisplayFirefoxDownloads(ProfilePath, DownloadFormat);
        DisplayFirefoxExtension(ProfilePath, ExtensionFormat);
        DisplayFirefoxLocalStorage(ProfilePath, LocalStorageFormat);
        DisplayFirefoxSessionStorage(ProfilePath, SessionStorageFormat);
        WriteLn;
      end;
  end;
end;

procedure ProcessChromiumProfile(const ProfilePath: string; DataType: TDataType;
  BrowserKind: TBrowserKind;
  const PasswordFormat: ChromiumPassword.TOutputFormat;
  const BookmarkFormat: ChromiumBookmark.TOutputFormat;
  const CookieFormat: ChromiumCookie.TOutputFormat;
  const HistoryFormat: ChromiumHistory.TOutputFormat;
  const DownloadFormat: ChromiumDownload.TOutputFormat;
  const ExtensionFormat: ChromiumExtension.TOutputFormat;
  const CreditCardFormat: ChromiumCreditCard.TOutputFormat);
begin
  case DataType of
    dtPassword:
      DisplayChromiumPasswords(ProfilePath,
        ChromiumPassword.TBrowserKind(BrowserKind), PasswordFormat);
    dtBookmark:
      DisplayChromiumBookmarks(ProfilePath,
        ChromiumBookmark.TBrowserKind(BrowserKind), BookmarkFormat);

    dtCookie:
      DisplayChromiumCookies(ProfilePath,
        ChromiumCookie.TBrowserKind(BrowserKind), CookieFormat);

    dtHistory:
      DisplayChromiumHistory(ProfilePath,
        ChromiumHistory.TBrowserKind(BrowserKind), HistoryFormat);
    dtDownload:
      DisplayChromiumDownloads(ProfilePath,
        ChromiumDownload.TBrowserKind(BrowserKind), DownloadFormat);
    dtExtension:
      DisplayChromiumExtension(ProfilePath,
        ChromiumExtension.TBrowserKind(BrowserKind), ExtensionFormat);
    dtCreditCard:
      DisplayChromiumCreditCards(ProfilePath,
        ChromiumCreditCard.TBrowserKind(BrowserKind), CreditCardFormat);

    dtAll:
      begin
        DisplayChromiumPasswords(ProfilePath,
          ChromiumPassword.TBrowserKind(BrowserKind), PasswordFormat);
        DisplayChromiumBookmarks(ProfilePath,
          ChromiumBookmark.TBrowserKind(BrowserKind), BookmarkFormat);
        DisplayChromiumCookies(ProfilePath,
          ChromiumCookie.TBrowserKind(BrowserKind), CookieFormat);

        DisplayChromiumHistory(ProfilePath,
          ChromiumHistory.TBrowserKind(BrowserKind), HistoryFormat);
        DisplayChromiumDownloads(ProfilePath,
          ChromiumDownload.TBrowserKind(BrowserKind), DownloadFormat);
        DisplayChromiumExtension(ProfilePath,
          ChromiumExtension.TBrowserKind(BrowserKind), ExtensionFormat);
        DisplayChromiumCreditCards(ProfilePath,
          ChromiumCreditCard.TBrowserKind(BrowserKind), CreditCardFormat);
        WriteLn;
      end;
  end;
end;

var
  i: Integer;
  Param, Value: string;
  ListOnly: Boolean;
  DataType: TDataType;
  BrowserType: TBrowserType;
  FirefoxPasswordFormat: FirefoxPassword.TOutputFormat;
  FirefoxHistoryFormat: FirefoxHistory.TOutputFormat;
  FirefoxBookmarkFormat: FirefoxBookmark.TOutputFormat;
  FirefoxCookieFormat: FirefoxCookie.TOutputFormat;
  FirefoxDownloadFormat: FirefoxDownload.TOutputFormat;
  FirefoxExtensionFormat: FirefoxExtension.TOutputFormat;
  FirefoxLocalStorageFormat: FirefoxLocalStorage.TOutputFormat;
  FirefoxSessionStorageFormat: FirefoxSessionStorage.TOutputFormat;
  ChromiumPasswordFormat: ChromiumPassword.TOutputFormat;
  ChromiumBookmarkFormat: ChromiumBookmark.TOutputFormat;
  ChromiumCookieFormat: ChromiumCookie.TOutputFormat;
  ChromiumHistoryFormat: ChromiumHistory.TOutputFormat;
  ChromiumDownloadFormat: ChromiumDownload.TOutputFormat;
  ChromiumExtensionFormat: ChromiumExtension.TOutputFormat;
  ChromiumCreditCardFormat: ChromiumCreditCard.TOutputFormat;

  BrowserDetector: TBrowserDetector;

begin
  WriteLn;
  WriteLn(' ____                                  _____        _        ______      _                  _');
  WriteLn('|  _ \                                |  __ \      | |      |  ____|    | |                | |');
  WriteLn('| |_) |_ __ _____      _____  ___ _ __| |  | | __ _| |_ __ _| |__  __  _| |_ _ __ __ _  ___| |_ ___  _ __ ');
  WriteLn('|  _ <|  __/ _ \ \ /\ / / __|/ _ \  __| |  | |/ _` | __/ _` |  __| \ \/ / __|  __/ _` |/ __| __/ _ \|  __|');
  WriteLn('| |_) | | | (_) \ V  V /\__ \  __/ |  | |__| | (_| | || (_| | |____ >  <| |_| | | (_| | (__| || (_) | |');
  WriteLn('|____/|_|  \___/ \_/\_/ |___/\___|_|  |_____/ \__,_|\__\__,_|______/_/\_\\__|_|  \__,_|\___|\__\___/|_|');
  WriteLn;

  BrowserDetector := TBrowserDetector.Create;
  try
    // Checking installed browsers...
    WriteLn('Checking installed browsers...');

    if not(BrowserDetector.IsChromeInstalled or
      BrowserDetector.IsFirefoxInstalled or BrowserDetector.IsBraveInstalled or
      BrowserDetector.IsEdgeInstalled) then
    begin
      WriteLn('No supported browsers found.');
      Exit;
    end;

    // Let user know which browsers were found
    WriteLn('Found: ', TBrowserDetector.GetBrowserName
      (BrowserDetector.IsChromeInstalled, BrowserDetector.IsFirefoxInstalled,
      BrowserDetector.IsBraveInstalled, BrowserDetector.IsEdgeInstalled));

    try
      // Check for help flag first
      for i := 1 to ParamCount do
        if (ParamStr(i) = '-h') or (ParamStr(i) = '--help') then
        begin
          PrintUsage;
          Exit;
        end;

      ListOnly := False;
      DataType := dtAll;
      BrowserType := btAll;

      // Set default formats
      FirefoxPasswordFormat := FirefoxPassword.ofCSV;
      FirefoxHistoryFormat := FirefoxHistory.ofCSV;
      FirefoxBookmarkFormat := FirefoxBookmark.ofCSV;
      FirefoxCookieFormat := FirefoxCookie.ofCSV;
      FirefoxDownloadFormat := FirefoxDownload.ofCSV;
      FirefoxExtensionFormat := FirefoxExtension.ofCSV;
      FirefoxLocalStorageFormat := FirefoxLocalStorage.ofCSV;
      FirefoxSessionStorageFormat := FirefoxSessionStorage.ofCSV;
      ChromiumPasswordFormat := ChromiumPassword.ofCSV;
      ChromiumHistoryFormat := ChromiumHistory.ofCSV;
      ChromiumBookmarkFormat := ChromiumBookmark.ofCSV;
      ChromiumCookieFormat := ChromiumCookie.ofCSV;
      ChromiumDownloadFormat := ChromiumDownload.ofCSV;
      ChromiumExtensionFormat := ChromiumExtension.ofCSV;
      ChromiumCreditCardFormat := ChromiumCreditCard.ofCSV;

      // Parse command line parameters
      i := 1;
      while i <= ParamCount do
      begin
        Param := ParamStr(i);

        if (Param = '-l') or (Param = '--list') then
          ListOnly := True
        else if (Param = '-b') or (Param = '--browser') then
        begin
          Inc(i);
          if i <= ParamCount then
          begin
            Value := LowerCase(ParamStr(i));
            if Value = 'firefox' then
              BrowserType := btFirefox
            else if Value = 'chrome' then
              BrowserType := btChrome // -->btChromium
            else
              BrowserType := btAll;
          end;
        end
        else if (Param = '-d') or (Param = '--data') then
        begin
          Inc(i);
          if i <= ParamCount then
          begin
            Value := LowerCase(ParamStr(i));
            if Value = 'password' then
              DataType := dtPassword
            else if Value = 'history' then
              DataType := dtHistory
            else if Value = 'bookmark' then
              DataType := dtBookmark
            else if Value = 'cookie' then
              DataType := dtCookie
            else if Value = 'download' then
              DataType := dtDownload
            else if Value = 'extension' then
              DataType := dtExtension
            else if Value = 'localstorage' then
              DataType := dtLocalStorage
            else if Value = 'sessionstorage' then
              DataType := dtSessionStorage
            else if Value = 'creditcard' then
              DataType := dtCreditCard
            else
              DataType := dtAll;
          end;
        end
        else if (Param = '-f') or (Param = '--format') then
        begin
          Inc(i);
          if i <= ParamCount then
          begin
            Value := LowerCase(ParamStr(i));
            if Value = 'human' then
            begin
              FirefoxPasswordFormat := FirefoxPassword.ofHuman;
              FirefoxHistoryFormat := FirefoxHistory.ofHuman;
              FirefoxBookmarkFormat := FirefoxBookmark.ofHuman;
              FirefoxCookieFormat := FirefoxCookie.ofHuman;
              FirefoxDownloadFormat := FirefoxDownload.ofHuman;
              FirefoxExtensionFormat := FirefoxExtension.ofHuman;
              FirefoxLocalStorageFormat := FirefoxLocalStorage.ofHuman;
              FirefoxSessionStorageFormat := FirefoxSessionStorage.ofHuman;
              ChromiumPasswordFormat := ChromiumPassword.ofHuman;
              ChromiumHistoryFormat := ChromiumHistory.ofHuman;
              ChromiumBookmarkFormat := ChromiumBookmark.ofHuman;
              ChromiumCookieFormat := ChromiumCookie.ofHuman;
              ChromiumDownloadFormat := ChromiumDownload.ofHuman;
              ChromiumExtensionFormat := ChromiumExtension.ofHuman;
              ChromiumCreditCardFormat := ChromiumCreditCard.ofHuman;
            end
            else if Value = 'json' then
            begin
              FirefoxPasswordFormat := FirefoxPassword.ofJSON;
              FirefoxHistoryFormat := FirefoxHistory.ofJSON;
              FirefoxBookmarkFormat := FirefoxBookmark.ofJSON;
              FirefoxCookieFormat := FirefoxCookie.ofJSON;
              FirefoxDownloadFormat := FirefoxDownload.ofJSON;
              FirefoxExtensionFormat := FirefoxExtension.ofJSON;
              FirefoxLocalStorageFormat := FirefoxLocalStorage.ofJSON;
              FirefoxSessionStorageFormat := FirefoxSessionStorage.ofJSON;
              ChromiumPasswordFormat := ChromiumPassword.ofJSON;
              ChromiumHistoryFormat := ChromiumHistory.ofJSON;
              ChromiumBookmarkFormat := ChromiumBookmark.ofJSON;
              ChromiumCookieFormat := ChromiumCookie.ofJSON;
              ChromiumDownloadFormat := ChromiumDownload.ofJSON;
              ChromiumExtensionFormat := ChromiumExtension.ofJSON;
              ChromiumCreditCardFormat := ChromiumCreditCard.ofJSON;
            end
            else
            begin
              FirefoxPasswordFormat := FirefoxPassword.ofCSV;
              FirefoxHistoryFormat := FirefoxHistory.ofCSV;
              FirefoxBookmarkFormat := FirefoxBookmark.ofCSV;
              FirefoxCookieFormat := FirefoxCookie.ofCSV;
              FirefoxDownloadFormat := FirefoxDownload.ofCSV;
              FirefoxExtensionFormat := FirefoxExtension.ofCSV;
              FirefoxLocalStorageFormat := FirefoxLocalStorage.ofCSV;
              FirefoxSessionStorageFormat := FirefoxSessionStorage.ofCSV;
              ChromiumPasswordFormat := ChromiumPassword.ofCSV;
              ChromiumHistoryFormat := ChromiumHistory.ofCSV;
              ChromiumBookmarkFormat := ChromiumBookmark.ofCSV;
              ChromiumCookieFormat := ChromiumCookie.ofCSV;
              ChromiumDownloadFormat := ChromiumDownload.ofCSV;
              ChromiumExtensionFormat := ChromiumExtension.ofCSV;
              ChromiumCreditCardFormat := ChromiumCreditCard.ofCSV;
            end;
          end;
        end;

        Inc(i);
      end;

      if ListOnly then
      begin
        case BrowserType of
          btFirefox:
            begin
              if BrowserDetector.IsFirefoxInstalled then
              begin
                WriteLn('Firefox Profiles:');
                FirefoxProfiles.ListProfiles;
              end
              else
                WriteLn('Firefox is not installed on this system.');
            end;
          btChrome:
            begin
              var
              ChromeHelper := TChromiumProfileHelper.Create(ChromiumProfiles.TBrowserKind.bkChrome);
              try
                if BrowserDetector.IsChromeInstalled then
                begin
                  WriteLn('Chrome Profiles:');
                  ChromeHelper.ListProfiles;
                end
                else
                  WriteLn('Chrome is not installed on this system.');
              finally
                ChromeHelper.Free;
              end;
            end;
          btEdge:
            begin
              var
              EdgeHelper := TChromiumProfileHelper.Create(ChromiumProfiles.TBrowserKind.bkEdge);
              try
                if BrowserDetector.IsEdgeInstalled then
                begin
                  WriteLn('Edge Profiles:');
                  EdgeHelper.ListProfiles;
                end
                else
                  WriteLn('Edge is not installed on this system.');
              finally
                EdgeHelper.Free;
              end;
            end;
          btAll:
            begin
              if BrowserDetector.IsFirefoxInstalled then
              begin
                WriteLn('Firefox Profiles:');
                FirefoxProfiles.ListProfiles;
                WriteLn;
              end;

              var
              ChromeHelper := TChromiumProfileHelper.Create(ChromiumProfiles.TBrowserKind.bkChrome);
              try
                if BrowserDetector.IsChromeInstalled then
                begin
                  WriteLn('Chrome Profiles:');
                  ChromeHelper.ListProfiles;
                  WriteLn;
                end;
              finally
                ChromeHelper.Free;
              end;

              var
              BraveHelper := TChromiumProfileHelper.Create(ChromiumProfiles.TBrowserKind.bkBrave);
              try
                if BrowserDetector.IsBraveInstalled then
                begin
                  WriteLn('Brave Profiles:');
                  BraveHelper.ListProfiles;
                  WriteLn;
                end;
              finally
                BraveHelper.Free;
              end;

              var
              EdgeHelper := TChromiumProfileHelper.Create(ChromiumProfiles.TBrowserKind.bkEdge);
              try
                if BrowserDetector.IsEdgeInstalled then
                begin
                  WriteLn('Edge Profiles:');
                  EdgeHelper.ListProfiles;
                end;
              finally
                EdgeHelper.Free;
              end;

              if not(BrowserDetector.IsFirefoxInstalled or
                BrowserDetector.IsChromeInstalled or
                BrowserDetector.IsBraveInstalled or
                BrowserDetector.IsEdgeInstalled) then
                WriteLn('No supported browsers found.');
            end;
        end;
        Exit;
      end;

      // Process Firefox profiles
      if BrowserType in [btFirefox, btAll] then
      begin
        if BrowserDetector.IsFirefoxInstalled then
        begin
          var
          FirefoxProfiles := GetFirefoxProfiles;
          for var Profile in FirefoxProfiles do
          begin
            ProcessFirefoxProfile(Profile.Path, DataType, FirefoxPasswordFormat,
              FirefoxHistoryFormat, FirefoxBookmarkFormat, FirefoxCookieFormat,
              FirefoxDownloadFormat, FirefoxExtensionFormat,
              FirefoxLocalStorageFormat, FirefoxSessionStorageFormat);
          end;
        end
        else if BrowserType = btFirefox then
          WriteLn('Firefox is not installed on this system.');
      end;

      // Process Chrome profiles
      if BrowserType in [btChrome, btAll] then
      begin
        if BrowserDetector.IsChromeInstalled then
        begin
          var
          ChromeHelper := TChromiumProfileHelper.Create(ChromiumProfiles.TBrowserKind.bkChrome);
          try
            var
            ChromeProfiles := ChromeHelper.GetProfiles;
            for var Profile in ChromeProfiles do
            begin
              ProcessChromiumProfile(Profile.Path, DataType, bkChrome,
                ChromiumPasswordFormat, ChromiumBookmarkFormat,
                ChromiumCookieFormat, ChromiumHistoryFormat,
                ChromiumDownloadFormat, ChromiumExtensionFormat,
                ChromiumCreditCardFormat);
            end;
          finally
            ChromeHelper.Free;
          end;
        end
        else if BrowserType = btChrome then
          WriteLn('Chrome is not installed on this system.');
      end;

      // Process Brave profiles
      if BrowserType in [btBrave, btAll] then
      begin
        if BrowserDetector.IsBraveInstalled then
        begin
          var
          BraveHelper := TChromiumProfileHelper.Create(ChromiumProfiles.TBrowserKind.bkBrave);
          try
            var
            BraveProfiles := BraveHelper.GetProfiles;
            for var Profile in BraveProfiles do
            begin
              ProcessChromiumProfile(Profile.Path, DataType, bkBrave,
                ChromiumPasswordFormat, ChromiumBookmarkFormat,
                ChromiumCookieFormat, ChromiumHistoryFormat,
                ChromiumDownloadFormat, ChromiumExtensionFormat,
                ChromiumCreditCardFormat);
            end;
          finally
            BraveHelper.Free;
          end;
        end
        else if BrowserType = btBrave then
          WriteLn('Brave is not installed on this system.');
      end;

      // Process Edge profiles
      if BrowserType in [btEdge, btAll] then
      begin
        if BrowserDetector.IsEdgeInstalled then
        begin
          var
          EdgeHelper := TChromiumProfileHelper.Create(ChromiumProfiles.TBrowserKind.bkEdge);
          try
            var
            EdgeProfiles := EdgeHelper.GetProfiles;
            for var Profile in EdgeProfiles do
            begin
              ProcessChromiumProfile(Profile.Path, DataType, bkEdge,
                ChromiumPasswordFormat, ChromiumBookmarkFormat,
                ChromiumCookieFormat, ChromiumHistoryFormat,
                ChromiumDownloadFormat, ChromiumExtensionFormat,
                ChromiumCreditCardFormat);
            end;
          finally
            EdgeHelper.Free;
          end;
        end
        else if BrowserType = btEdge then
          WriteLn('Edge is not installed on this system.');
      end;

      WriteLn('Press Enter to exit...');
      ReadLn;

    except
      on E: Exception do
      begin
        WriteLn('Error: ', E.Message);
        WriteLn('Press Enter to exit...');
        ReadLn;
        ExitCode := 1;
      end;
    end;

  finally
    BrowserDetector.Free;
  end;

end.
