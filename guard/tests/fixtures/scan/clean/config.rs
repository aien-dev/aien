// Synthetic fixture: credentials come from the environment, never literals.
fn token() -> Option<String> {
    let token = std::env::var("GH_TOKEN").ok();
    token
}
