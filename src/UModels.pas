unit UModels;

interface

uses
  System.SysUtils;

{$SCOPEDENUMS ON}

type
  TProgressMode = (pmIndeterminate, pmDeterminate);

  TGitResult = record
    ExitCode: Cardinal;
    OutputText: string;
    OutputLines: TArray<string>;
  end;

  TRepoCacheEntry = record
    OriginUrl: string;
    LastFetchUtc: string;
    LastFetchOk: Boolean;
    LastFetchError: string;
  end;

  TRepoCacheUpdate = record
    Key: string;
    OriginUrl: string;
    LastFetchUtc: string;
    LastFetchOk: Boolean;
    LastFetchError: string;
    HasLastFetchOk: Boolean;
  end;

  TRepoStatus = record
    RepoRoot: string;
    MatchedFolders: TArray<string>;
    Branch: string;
    IsSubmodule: Boolean;
    SubmoduleMainRemoteRef: string;
    SubmoduleNeedsMainFastForward: Boolean;
    HasOrigin: Boolean;
    Upstream: string;
    CanCompare: Boolean;
    Behind: Integer;
    Ahead: Integer;
    IsOutOfDate: Boolean;
    HasUnpushed: Boolean;
    IsDirty: Boolean;
    DirtySummary: string;
    FetchFailed: Boolean;
    FetchError: string;
    HasProblem: Boolean;
    GitDirPath: string;
    GitDirWritable: Boolean;
    GitDirReadOnly: Boolean;
    GitDirError: string;
    ModulesDirPath: string;
    ModulesDirWritable: Boolean;
    ModulesDirReadOnly: Boolean;
    ModulesDirError: string;
    CacheUpdate: TRepoCacheUpdate;
  end;

  TScanSummary = record
    CandidateCount: Integer;
    RepoCount: Integer;
    ProblemCount: Integer;
    CleanCount: Integer;
    SkippedDueToCap: Boolean;
    ElapsedMs: Int64;
  end;

implementation

end.
