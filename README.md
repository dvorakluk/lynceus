<div align="center">
  <img src="./images/icon_512@2x.png" width="128" alt="Logo"/>
  <h1>Lynceus</h1>
  <p><em>Wisdom in every notification</em></p>
</div>

Lynceus is a lightweight agent that keeps you informed about the things that matter to your workflow. Named after the keen-sighted Argonaut of Greek mythology (and represented by a watchful owl), Lynceus monitors feeds and git forges, delivering desktop notifications when updates occur.

Whether you're tracking blog posts, monitoring project releases, or waiting for that critical PR to merge, Lynceus handles the watching so you can focus on building. It's designed for developers who need to stay connected without constantly checking multiple sources.

## Configuration

Lynceus currently uses JSON for its configuration file. Is JSON my favorite choice for human-written configuration? Absolutely not. But it’s intentionally being used for now to avoid adding extra dependencies or committing too early to yet another configuration language while the set of configuration options is still taking shape.

Configuration is organized around **sources**, each source tells Lynceus what to watch.
