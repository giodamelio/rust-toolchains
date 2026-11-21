// `-d install_skills=true` is accepted even when the skills module, and so
// the question, is left out, and then must not trigger a download.
let skills = variable::is_set("install_skills")
    && variable::get("modules").contains("skills")
    && `${variable::get("install_skills")}` == "true";

let modules = "";
for name in variable::get("modules") {
    modules += name + ",";
}

file::write(".init-answers", "vcs=" + variable::get("vcs") + "\ninstall_skills=" + skills + "\nmodules=" + modules + "\n");
