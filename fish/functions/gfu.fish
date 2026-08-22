function gfu -d "git commit and push all the way"
  git commit --all --amend --no-edit --no-verify; git push --force-with-lease --no-verify
end
