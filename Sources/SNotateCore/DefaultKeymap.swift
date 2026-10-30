/// The built-in bindings (SN-501, SN-503). `[` and `]` are the sibling
/// case, as in sView; z-order takes `cmd-[` and `cmd-]`. The keymap file that overlays
/// them, `~/.config/snotate/keymap` (SN-504), arrives with the config branch.
public enum DefaultKeymap {
    public static let keymap = Keymap<Command>.parse(text).keymap

    public static let text = """
        # sNotate keymap. One binding per line: <keys> <command> [args]
        # Keys are characters (case matters) or named keys: space enter tab esc
        # backspace delete left right up down home end pageup pagedown f1..f12
        # hash lt gt, with cmd- ctrl- alt- shift- modifiers. Shift is a letter's
        # case (G, cmd-Z); shift- is for named keys (shift-left).

        # steps
        j next
        k previous
        gg first
        G last
        J move-step-later
        K move-step-earlier
        dd remove-step
        : command-line
        # views
        cmd-1 view-step
        cmd-2 view-storyboard
        i edit-caption
        # cases
        ] case-next
        [ case-previous

        # tools
        v tool select
        esc tool select
        a tool arrow
        r tool rectangle
        e tool ellipse
        n tool counter
        N restart-counter
        t tool text
        h tool highlight
        b tool blur
        c tool crop
        C crop-previous
        # the step
        x exclude
        gt stamp-following
        lt stamp-previous

        # the selection
        cmd-a select-all
        backspace delete
        delete delete
        cmd-d duplicate
        f fill
        enter edit
        cmd-[ send-backward
        cmd-] bring-forward
        left nudge-left
        right nudge-right
        up nudge-up
        down nudge-down
        shift-left nudge-left-10
        shift-right nudge-right-10
        shift-up nudge-up-10
        shift-down nudge-down-10

        # view
        = zoom-fit
        0 zoom-actual
        + zoom-in
        - zoom-out
        z zoom-area
        # presets
        1 preset 1
        2 preset 2
        3 preset 3
        4 preset 4
        5 preset 5
        6 preset 6
        7 preset 7
        8 preset 8
        9 preset 9

        # export
        cmd-e export
        cmd-E export-step
        cmd-C copy-step
        # history
        cmd-z undo
        cmd-Z redo

        # help
        ? help
        """
}
