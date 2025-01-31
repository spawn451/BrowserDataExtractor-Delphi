unit FirefoxBookmark;

interface

uses
  System.SysUtils,
  System.Classes,
  System.IOUtils,
  System.Generics.Collections,
  System.Generics.Defaults,
  System.DateUtils,
  System.JSON,
  System.StrUtils,
  Uni,
  SQLiteUniProvider;

type
  TOutputFormat = (ofHuman, ofJSON, ofCSV);

  TBookmarkType = (btURL, btFolder);

  TBookmarkItem = record
    ID: Int64;
    Name: string;
    URL: string;
    BookmarkType: TBookmarkType;
    DateAdded: TDateTime;
  end;

  TBookmarkItems = TArray<TBookmarkItem>;

  TFirefoxBookmarkHelper = class
  private
    FProfilePath: string;
    FOutputFormat: TOutputFormat;
    FSQLiteConnection: TUniConnection;

  const
    QUERY_FIREFOX_BOOKMARK = 'SELECT id, url, type, ' +
      'strftime(''%Y-%m-%d %H:%M:%S'', dateAdded/1000000, ''unixepoch'', ''localtime'') as formatted_date, '
      + 'title ' +
      'FROM (SELECT * FROM moz_bookmarks INNER JOIN moz_places ON moz_bookmarks.fk=moz_places.id)';

    CLOSE_JOURNAL_MODE = 'PRAGMA journal_mode=off';

    function GetProfileName: string;
    procedure EnsureResultsDirectory;
    procedure OutputHuman(const Bookmarks: TBookmarkItems);
    procedure OutputJSON(const Bookmarks: TBookmarkItems);
    procedure OutputCSV(const Bookmarks: TBookmarkItems);
    procedure OutputBookmarks(const Bookmarks: TBookmarkItems);
    function GetBookmarkType(TypeValue: Int64): TBookmarkType;
  public
    constructor Create(const AProfilePath: string);
    destructor Destroy; override;
    function GetBookmarks: TBookmarkItems;
    procedure SortBookmarksByDate(var Bookmarks: TBookmarkItems);
    function GetBookmarkCount: Integer;
    property OutputFormat: TOutputFormat read FOutputFormat write FOutputFormat;
  end;

implementation

function TFirefoxBookmarkHelper.GetProfileName: string;
var
  ProfileFolder: string;
begin
  ProfileFolder := ExtractFileName(ExcludeTrailingPathDelimiter(FProfilePath));
  Result := StringReplace(ProfileFolder, '.', '_', [rfReplaceAll]);
end;

function TFirefoxBookmarkHelper.GetBookmarkType(TypeValue: Int64)
  : TBookmarkType;
begin
  case TypeValue of
    1:
      Result := btURL;
  else
    Result := btFolder;
  end;
end;

procedure TFirefoxBookmarkHelper.EnsureResultsDirectory;
var
  ResultsDir: string;
begin
  ResultsDir := TPath.Combine(GetCurrentDir, 'results');
  if not TDirectory.Exists(ResultsDir) then
    TDirectory.CreateDirectory(ResultsDir);
end;

procedure TFirefoxBookmarkHelper.OutputHuman(const Bookmarks: TBookmarkItems);
var
  OutputFile: TextFile;
  FileName, FilePath: string;
begin
  EnsureResultsDirectory;
  FileName := Format('firefox_%s_bookmarks.txt', [GetProfileName]);
  FilePath := TPath.Combine(TPath.Combine(GetCurrentDir, 'results'), FileName);
  AssignFile(OutputFile, FilePath);
  try
    Rewrite(OutputFile);
    for var Item in Bookmarks do
    begin
      WriteLn(OutputFile);
      WriteLn(OutputFile, 'Name: ', Item.Name);
      WriteLn(OutputFile, 'URL: ', Item.URL);
      WriteLn(OutputFile, 'Type: ', IfThen(Item.BookmarkType = btURL, 'URL',
        'Folder'));
      WriteLn(OutputFile, 'Date Added: ', FormatDateTime('yyyy-mm-dd hh:nn:ss',
        Item.DateAdded));
      WriteLn(OutputFile, '----------------------------------------');
    end;
    WriteLn('[FIREFOX] Bookmarks saved to: ', FilePath);
  finally
    CloseFile(OutputFile);
  end;
end;

procedure TFirefoxBookmarkHelper.OutputJSON(const Bookmarks: TBookmarkItems);
var
  JSONArray: TJSONArray;
  JSONObject: TJSONObject;
  FileName, FilePath, JSONString: string;
begin
  EnsureResultsDirectory;
  JSONArray := TJSONArray.Create;
  try
    for var Item in Bookmarks do
    begin
      JSONObject := TJSONObject.Create;
      JSONObject.AddPair('name', TJSONString.Create(Item.Name));
      JSONObject.AddPair('url', TJSONString.Create(Item.URL));
      JSONObject.AddPair('type', TJSONString.Create(IfThen(Item.BookmarkType = btURL, 'url', 'folder')));
      JSONObject.AddPair('dateAdded', FormatDateTime('yyyy-mm-dd hh:nn:ss', Item.DateAdded));
      JSONArray.AddElement(JSONObject);
    end;

    FileName := Format('firefox_%s_bookmarks.json', [GetProfileName]);
    FilePath := TPath.Combine(TPath.Combine(GetCurrentDir, 'results'), FileName);

    // Convert JSON to string
    JSONString := JSONArray.Format(2);

    // Replace escaped forward slashes \/ with /
    JSONString := StringReplace(JSONString, '\/', '/', [rfReplaceAll]);

    // Save the modified JSON string
    TFile.WriteAllText(FilePath, JSONString);

    WriteLn('[FIREFOX] Bookmarks saved to: ', FilePath);
  finally
    JSONArray.Free;
  end;
end;

procedure TFirefoxBookmarkHelper.OutputCSV(const Bookmarks: TBookmarkItems);
var
  OutputFile: TextFile;
  FileName, FilePath: string;
begin
  EnsureResultsDirectory;
  FileName := Format('firefox_%s_bookmarks.csv', [GetProfileName]);
  FilePath := TPath.Combine(TPath.Combine(GetCurrentDir, 'results'), FileName);
  AssignFile(OutputFile, FilePath);
  try
    Rewrite(OutputFile);
    WriteLn(OutputFile, 'Name,URL,Type,DateAdded');

    for var Item in Bookmarks do
    begin
      WriteLn(OutputFile, Format('"%s","%s","%s","%s"',
        [StringReplace(Item.Name, '"', '""', [rfReplaceAll]),
        StringReplace(Item.URL, '"', '""', [rfReplaceAll]),
        IfThen(Item.BookmarkType = btURL, 'url', 'folder'),
        FormatDateTime('yyyy-mm-dd hh:nn:ss', Item.DateAdded)]));
    end;

    WriteLn('[FIREFOX] Bookmarks saved to: ', FilePath);
  finally
    CloseFile(OutputFile);
  end;
end;

procedure TFirefoxBookmarkHelper.OutputBookmarks(const Bookmarks
  : TBookmarkItems);
begin
  case FOutputFormat of
    ofHuman:
      OutputHuman(Bookmarks);
    ofJSON:
      OutputJSON(Bookmarks);
    ofCSV:
      OutputCSV(Bookmarks);
  end;
end;

constructor TFirefoxBookmarkHelper.Create(const AProfilePath: string);
begin
  inherited Create;
  FProfilePath := AProfilePath;
  FOutputFormat := ofCSV;
  FSQLiteConnection := TUniConnection.Create(nil);
  FSQLiteConnection.ProviderName := 'SQLite';
  FSQLiteConnection.LoginPrompt := False;
  FSQLiteConnection.SpecificOptions.Values['Direct'] := 'True';
end;

destructor TFirefoxBookmarkHelper.Destroy;
begin
  if Assigned(FSQLiteConnection) then
  begin
    if FSQLiteConnection.Connected then
      FSQLiteConnection.Disconnect;
    FSQLiteConnection.Free;
  end;
  inherited;
end;

function TFirefoxBookmarkHelper.GetBookmarks: TBookmarkItems;
var
 Query: TUniQuery;
 BookmarkDb, TempDb: string;
 FS: TFormatSettings;
begin
 SetLength(Result, 0);
 BookmarkDb := TPath.Combine(FProfilePath, 'places.sqlite');

 if not FileExists(BookmarkDb) then
   Exit;

 // Create temp copy of database
 TempDb := TPath.Combine(TPath.GetTempPath, Format('places_%s.sqlite',
   [TGUID.NewGuid.ToString]));
 try
   TFile.Copy(BookmarkDb, TempDb);
   FSQLiteConnection.Database := TempDb;
   FSQLiteConnection.Connect;
   Query := TUniQuery.Create(nil);
   try
     Query.Connection := FSQLiteConnection;
     Query.SQL.Text := CLOSE_JOURNAL_MODE;
     Query.ExecSQL;
     Query.SQL.Text := QUERY_FIREFOX_BOOKMARK;
     Query.Open;

     while not Query.Eof do
     begin
       SetLength(Result, Length(Result) + 1);
       with Result[High(Result)] do
       begin
         ID := Query.FieldByName('id').AsLargeInt;
         Name := Query.FieldByName('title').AsString;
         URL := Query.FieldByName('url').AsString;
         BookmarkType := GetBookmarkType(Query.FieldByName('type').AsInteger);

         var DateStr := Query.FieldByName('formatted_date').AsString;

         try
           FS := TFormatSettings.Create;
           FS.DateSeparator := '-';
           FS.TimeSeparator := ':';
           FS.ShortDateFormat := 'yyyy-mm-dd';
           FS.LongTimeFormat := 'hh:nn:ss';
           DateAdded := StrToDateTime(DateStr, FS);
         except
           on E: Exception do
           begin
             WriteLn('Error parsing date: ' + DateStr + ' - ' + E.Message);
             DateAdded := 0;  // Default value if parsing fails
           end;
         end;
       end;
       Query.Next;
     end;

     // Sort and output bookmarks in selected format
     if Length(Result) > 0 then
     begin
       SortBookmarksByDate(Result);
       OutputBookmarks(Result);
     end;

   finally
     Query.Free;
     FSQLiteConnection.Disconnect;
   end;

 finally
   // Delete temporary database copy
   if FileExists(TempDb) then
     TFile.Delete(TempDb);
 end;
end;

procedure TFirefoxBookmarkHelper.SortBookmarksByDate(var Bookmarks
  : TBookmarkItems);
var
  i, j: Integer;
  temp: TBookmarkItem;
begin
  for i := Low(Bookmarks) to High(Bookmarks) - 1 do
    for j := i + 1 to High(Bookmarks) do
      if Bookmarks[i].DateAdded < Bookmarks[j].DateAdded then
      begin
        temp := Bookmarks[i];
        Bookmarks[i] := Bookmarks[j];
        Bookmarks[j] := temp;
      end;
end;

function TFirefoxBookmarkHelper.GetBookmarkCount: Integer;
var
  Query: TUniQuery;
  BookmarkDb: string;
begin
  Result := 0;
  BookmarkDb := TPath.Combine(FProfilePath, 'places.sqlite');

  if not FileExists(BookmarkDb) then
    Exit;

  FSQLiteConnection.Database := BookmarkDb;

  try
    FSQLiteConnection.Connect;
    Query := TUniQuery.Create(nil);
    try
      Query.Connection := FSQLiteConnection;
      Query.SQL.Text := 'SELECT COUNT(*) as count FROM moz_bookmarks';
      Query.Open;
      Result := Query.FieldByName('count').AsInteger;
    finally
      Query.Free;
    end;
  except
    on E: Exception do
      WriteLn('Error getting bookmark count: ', E.Message);
  end;
end;

end.
