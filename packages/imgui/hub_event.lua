
local Evt ={
    --Scene&Entity
    HierarchyChange = "Editor_HierarchyChange",
    EntityInfo = "Editor_EntityInfo", --type="pick" or "editor","auto"
    EntityPick = "Editor_EntityPick",
    WatchEntity ="Editor_WatchEntity",
    ModifyComponent ="Editor_ModifyComponent",
    ResponseWorldInfo ="Editor_ResponseWorldInfo",
    RequestWorldInfo ="Editor_RequestWorldInfo",
    --tool
    RunScript = "Editor_RunScript",
}
return Evt