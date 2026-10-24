object FolderTreeFrame: TFolderTreeFrame
  Left = 0
  Top = 0
  Width = 260
  Height = 480
  Align = alClient
  TabOrder = 0
  object FolderTree: TFolderTreeView
    Left = 0
    Top = 20
    Width = 260
    Height = 440
    Align = alClient
    CheckBoxes = True
    CheckStyles = [csPartial]
    HideSelection = False
    PopupMenu = FolderPopup
    ReadOnly = True
    TabOrder = 0
    OnCheckStateChanged = FolderTreeCheckStateChanged
    OnContextPopup = FolderTreeContextPopup
    OnCollapsed = FolderTreeCollapsed
    OnDeletion = FolderTreeDeletion
    OnExpanded = FolderTreeExpanded
    OnExpanding = FolderTreeExpanding
    OnKeyDown = FolderTreeKeyDown
  end
  object HeadingText: TStaticText
    Left = 0
    Top = 0
    Width = 260
    Height = 20
    Align = alTop
    AutoSize = False
    Caption = 'Fol&ders'
    FocusControl = FolderTree
    TabOrder = 1
    TabStop = False
  end
  object StatusText: TStaticText
    Left = 0
    Top = 460
    Width = 260
    Height = 20
    Align = alBottom
    AutoSize = False
    Caption = 'Space changes folder inclusion.'
    TabOrder = 2
    TabStop = False
  end
  object DeliveryTimer: TTimer
    Enabled = False
    Interval = 25
    OnTimer = DeliveryTimerTimer
    Left = 208
    Top = 32
  end
  object FolderPopup: TPopupMenu
    AutoPopup = False
    Left = 208
    Top = 72
    object DiscoverHereItem: TMenuItem
      Caption = 'Update Repo list &here'
      Enabled = False
      OnClick = DiscoverHereItemClick
    end
  end
end
