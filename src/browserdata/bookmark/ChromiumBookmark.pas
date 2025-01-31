unit ChromiumBookmark;

interface

uses
  System.SysUtils,
  System.Classes,
  System.IOUtils,
  System.Generics.Collections,
  System.Generics.Defaults,
  System.DateUtils,
  System.JSON,
  System.StrUtils;

type
  TBrowserKind = (bkChrome, bkBrave, bkEdge);

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

  TChromiumBookmarkHelper = class
  private
    FProfilePath: string;
    FOutputFormat: TOutputFormat;
    FBrowserKind: TBrowserKind;
    function GetProfileName: string;
    function GetBrowserPrefix: string;
    procedure EnsureResultsDirectory;
    procedure OutputHuman(const Bookmarks: TBookmarkItems);
    procedure OutputJSON(const Bookmarks: TBookmarkItems);
    procedure OutputCSV(const Bookmarks: TBookmarkItems);
    procedure OutputBookmarks(const Bookmarks: TBookmarkItems);
    procedure ProcessBookmarkNode(const Node: TJSONObject;
      var Bookmarks: TBookmarkItems);
    function GetBookmarkType(const TypeStr: string): TBookmarkType;
    function ChromiumTimeToDateTime(TimeStamp: Int64): TDateTime;
  public
    constructor Create(const AProfilePath: string;
      ABrowserKind: TBrowserKind = bkChrome);
    destructor Destroy; override;
    function GetBookmarks: TBookmarkItems;
    procedure SortBookmarksByDate(var Bookmarks: TBookmarkItems);
    function GetBookmarkCount: Integer;
    property OutputFormat: TOutputFormat read FOutputFormat write FOutputFormat;
  end;

implementation

function TChromiumBookmarkHelper.GetProfileName: string;
var
  ProfileFolder: string;
begin
  ProfileFolder := ExtractFileName(ExcludeTrailingPathDelimiter(FProfilePath));
  Result := StringReplace(ProfileFolder, ' ', '_', [rfReplaceAll]);
end;

function TChromiumBookmarkHelper.GetBrowserPrefix: string;
begin
  case FBrowserKind of
    bkChrome:
      Result := 'chrome';
    bkBrave:
      Result := 'brave';
    bkEdge:
      Result := 'edge';
  end;
end;

function TChromiumBookmarkHelper.GetBookmarkType(const TypeStr: string)
  : TBookmarkType;
begin
  if TypeStr = 'url' then
    Result := btURL
  else
    Result := btFolder;
end;

function TChromiumBookmarkHelper.ChromiumTimeToDateTime(TimeStamp: Int64)
  : TDateTime;
const
  ChromiumTimeStart = 11644473600; // Seconds between 1601-01-01 and 1970-01-01
begin
  Result := UnixToDateTime((TimeStamp div 1000000) - ChromiumTimeStart);
end;

procedure TChromiumBookmarkHelper.ProcessBookmarkNode(const Node: TJSONObject;
  var Bookmarks: TBookmarkItems);
var
  NodeType, URL, Name: string;
  Children: TJSONArray;
  ChildNode: TJSONValue;
  TimeStamp: Int64;
  ConvertedTime: TDateTime;
  BookmarkName, BookmarkURL: string;
begin
  if not Node.TryGetValue<string>('type', NodeType) then
    Exit;

  if NodeType = 'url' then
  begin
    Node.TryGetValue<string>('url', BookmarkURL);
    Node.TryGetValue<string>('name', BookmarkName);

    if Node.TryGetValue<Int64>('date_added', TimeStamp) then
    begin
      ConvertedTime := ChromiumTimeToDateTime(TimeStamp);
      SetLength(Bookmarks, Length(Bookmarks) + 1);
      with Bookmarks[High(Bookmarks)] do
      begin
        ID := Length(Bookmarks);
        Name := BookmarkName;
        URL := BookmarkURL;
        BookmarkType := btURL;
        DateAdded := ConvertedTime;
      end;
    end;
  end;

  if Node.TryGetValue<TJSONArray>('children', Children) then
  begin
    for ChildNode in Children do
    begin
      if ChildNode is TJSONObject then
        ProcessBookmarkNode(TJSONObject(ChildNode), Bookmarks);
    end;
  end;
end;

procedure TChromiumBookmarkHelper.EnsureResultsDirectory;
var
  ResultsDir: string;
begin
  ResultsDir := TPath.Combine(GetCurrentDir, 'results');
  if not TDirectory.Exists(ResultsDir) then
    TDirectory.CreateDirectory(ResultsDir);
end;

procedure TChromiumBookmarkHelper.OutputHuman(const Bookmarks: TBookmarkItems);
var
  OutputFile: TextFile;
  FileName, FilePath: string;
begin
  EnsureResultsDirectory;
  FileName := Format('%s_%s_bookmarks.txt', [GetBrowserPrefix, GetProfileName]);
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
    WriteLn(Format('[%s] Bookmarks saved to: %s', [GetBrowserPrefix.ToUpper,
      FilePath]));
  finally
    CloseFile(OutputFile);
  end;
end;

procedure TChromiumBookmarkHelper.OutputJSON(const Bookmarks: TBookmarkItems);
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
      JSONObject.AddPair('type',
        TJSONString.Create(IfThen(Item.BookmarkType = btURL, 'url', 'folder')));
      JSONObject.AddPair('dateAdded', FormatDateTime('yyyy-mm-dd hh:nn:ss',
        Item.DateAdded));
      JSONArray.AddElement(JSONObject);
    end;

    FileName := Format('%s_%s_bookmarks.json',
      [GetBrowserPrefix, GetProfileName]);
    FilePath := TPath.Combine(TPath.Combine(GetCurrentDir, 'results'),
      FileName);

    JSONString := JSONArray.Format(2);
    JSONString := StringReplace(JSONString, '\/', '/', [rfReplaceAll]);
    TFile.WriteAllText(FilePath, JSONString);

    WriteLn(Format('[%s] Bookmarks saved to: %s', [GetBrowserPrefix.ToUpper,
      FilePath]));
  finally
    JSONArray.Free;
  end;
end;

procedure TChromiumBookmarkHelper.OutputCSV(const Bookmarks: TBookmarkItems);
var
  OutputFile: TextFile;
  FileName, FilePath: string;
begin
  EnsureResultsDirectory;
  FileName := Format('%s_%s_bookmarks.csv', [GetBrowserPrefix, GetProfileName]);
  FilePath := TPath.Combine(TPath.Combine(GetCurrentDir, 'results'), FileName);
  AssignFile(OutputFile, FilePath);
  try
    Rewrite(OutputFile);
    WriteLn(OutputFile, 'Name,URL,Type,DateAdded');

    for var Item in Bookmarks do
    begin
      try
        WriteLn(OutputFile, Format('"%s","%s","%s","%s"',
          [StringReplace(Item.Name, '"', '""', [rfReplaceAll]),
          StringReplace(Item.URL, '"', '""', [rfReplaceAll]),
          IfThen(Item.BookmarkType = btURL, 'url', 'folder'),
          FormatDateTime('yyyy-mm-dd hh:nn:ss', Item.DateAdded)]));
      except
        on E: Exception do
          WriteLn('Error writing bookmark: ', E.Message);
      end;
    end;

    WriteLn(Format('[%s] Bookmarks saved to: %s', [GetBrowserPrefix.ToUpper,
      FilePath]));
  finally
    CloseFile(OutputFile);
  end;
end;

procedure TChromiumBookmarkHelper.OutputBookmarks(const Bookmarks
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

constructor TChromiumBookmarkHelper.Create(const AProfilePath: string;
  ABrowserKind: TBrowserKind = bkChrome);
begin
  inherited Create;
  FProfilePath := AProfilePath;
  FBrowserKind := ABrowserKind;
  FOutputFormat := ofCSV;
end;

destructor TChromiumBookmarkHelper.Destroy;
begin
  inherited;
end;

function TChromiumBookmarkHelper.GetBookmarks: TBookmarkItems;
var
  BookmarkFile: string;
  JSONText: string;
  RootObject: TJSONObject;
  RootsObject: TJSONObject;
  BookmarkBar, Other: TJSONObject;
begin
  SetLength(Result, 0);
  BookmarkFile := TPath.Combine(FProfilePath, 'Bookmarks');

  if not FileExists(BookmarkFile) then
  begin
    WriteLn(Format('[%s Debug] Bookmark file not found',
      [GetBrowserPrefix.ToUpper]));
    Exit;
  end;

  try
    JSONText := TFile.ReadAllText(BookmarkFile);
    RootObject := TJSONObject.ParseJSONValue(JSONText) as TJSONObject;
    try
      if RootObject.TryGetValue<TJSONObject>('roots', RootsObject) then
      begin
        if RootsObject.TryGetValue<TJSONObject>('bookmark_bar', BookmarkBar)
        then
          ProcessBookmarkNode(BookmarkBar, Result);

        if RootsObject.TryGetValue<TJSONObject>('other', Other) then
          ProcessBookmarkNode(Other, Result);
      end;

      if Length(Result) > 0 then
      begin
        SortBookmarksByDate(Result);
      end;
    finally
      RootObject.Free;
    end;
  except
    on E: Exception do
      WriteLn(Format('[%s] Error processing bookmarks: %s',
        [GetBrowserPrefix.ToUpper, E.Message]));
  end;

  if Length(Result) > 0 then
  begin
    OutputBookmarks(Result);
  end;
end;

procedure TChromiumBookmarkHelper.SortBookmarksByDate(var Bookmarks
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

function TChromiumBookmarkHelper.GetBookmarkCount: Integer;
var
  BookmarkFile: string;
  JSONText: string;
  RootObject: TJSONObject;
  Count: Integer;

  function CountBookmarksInNode(const Node: TJSONObject): Integer;
  var
    NodeType: string;
    Children: TJSONArray;
    ChildNode: TJSONValue;
  begin
    Result := 0;

    if not Node.TryGetValue<string>('type', NodeType) then
      Exit;

    if NodeType = 'url' then
      Inc(Result);

    if Node.TryGetValue<TJSONArray>('children', Children) then
    begin
      for ChildNode in Children do
      begin
        if ChildNode is TJSONObject then
          Inc(Result, CountBookmarksInNode(TJSONObject(ChildNode)));
      end;
    end;
  end;

begin
  Result := 0;
  BookmarkFile := TPath.Combine(FProfilePath, 'Bookmarks');

  if not FileExists(BookmarkFile) then
    Exit;

  try
    JSONText := TFile.ReadAllText(BookmarkFile);
    RootObject := TJSONObject.ParseJSONValue(JSONText) as TJSONObject;
    try
      if Assigned(RootObject) then
      begin
        Count := 0;
        var
          RootsObject: TJSONObject;
        if RootObject.TryGetValue<TJSONObject>('roots', RootsObject) then
        begin
          var
            BookmarkBar, Other: TJSONObject;
          if RootsObject.TryGetValue<TJSONObject>('bookmark_bar', BookmarkBar)
          then
            Inc(Count, CountBookmarksInNode(BookmarkBar));
          if RootsObject.TryGetValue<TJSONObject>('other', Other) then
            Inc(Count, CountBookmarksInNode(Other));
        end;
        Result := Count;
      end;
    finally
      RootObject.Free;
    end;
  except
    on E: Exception do
      WriteLn(Format('[%s] Error getting bookmark count: %s',
        [GetBrowserPrefix.ToUpper, E.Message]));
  end;
end;

end.
