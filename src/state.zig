pub const State = enum {
    main_menu,
    tileset,
    editor,
    palettes,
    preview,
    about,
    quit,
};
pub const StateMachine = struct {
    current: State,
    next: ?State,
    hot: bool = false,
    pub fn init(current: State) StateMachine {
        return StateMachine{ .current = current, .next = null, .hot = true };
    }
    pub fn goTo(self: *StateMachine, next: State) void {
        self.next = next;
    }
    pub fn update(self: *StateMachine) void {
        if (self.next) |next| {
            self.current = next;
            self.next = null;
            self.hot = true;
        }
    }
    pub fn is(self: StateMachine, target: State) bool {
        return self.current == target;
    }
};
