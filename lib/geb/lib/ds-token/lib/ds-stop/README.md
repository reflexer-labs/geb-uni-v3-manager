<h2>DSStop
  <small class="text-muted">
    <a href="https://github.com/dapphub/ds-stop"><span class="fa fa-github"></span></a>
  </small>
</h2>

_DSAuth-protected stop and start_

A simple package that adds a stoppable modifier, with DSAuth protected `stop` 
and `start` functions. Decorating a function with the `stoppable` modifier will 
ensure that it can only execute if the state is not `stopped`.
  
Useful in situations where one needs to halt a system for maintenance, in case 
of emergency, or to simply wind it down after a temporary lifespan.

### Actions

#### `stop`
Set `stopped` to true (requires auth)

#### `start`
Set `stopped` to false (requires auth)
