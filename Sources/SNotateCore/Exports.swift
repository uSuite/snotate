// SNotateCore re-exports the shared code, so the app sees one module.
@_exported import SCommon

/// Foundation also declares a `SortOrder`; this module's name wins over
/// both imports, so `SortOrder` keeps meaning the shared folder sort here.
public typealias SortOrder = SCommon.SortOrder
