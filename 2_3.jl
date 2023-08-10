using Gurobi,JuMP
using Plots, Random, Printf, XLSX, CSV, DataFrames, Distributions, MathOptInterface

# SETS and DATA

GEN_S=["S1","S2","S3","S4"]                  # price MAKER generators
GEN_O=["O1","O2","O3","O4"]                  # price TAKER generators
DEMAND=["D1","D2","D3","D4"]                 # demand
NODE=["N1","N2","N3","N4","N5","N6"]         # nodes

S=length(GEN_S)
O=length(GEN_O)
D=length(DEMAND)
N=length(NODE)
M=N

D_Location=[3 4 5 6]    # demand location
S_Location=[1 2 3 6]    # price MAKER generators locations
O_Location=[1 2 3 5]    # price TAKER generators locations

D_quantity=[200 400 300 250]         # MW
D_bid_price=[26.5 24.7 23.1 22.5]    # euro/MWh

S_capacity=[155 100 155 197]     # MW
O_capacity=[0.75*450 350 210 80]      # MW

S_cost=[15.2 23.4 15.2 19.1]     # euro/MWh
O_cost=[0 5 20.1 24.7]           # euro/MWh

susceptance=50
BB=susceptance

N_capacity=300   #  same line capacity for all the lines

N_table=[
    0 1 1 0 0 0;
    1 0 1 1 0 0;
    1 1 0 0 0 1;
    0 1 0 0 1 1;
    0 0 0 1 0 1;
    0 0 1 1 1 0

]

Big_M = 10^4


TWO_THREE= Model(Gurobi.Optimizer)

@variable(TWO_THREE, S_prod[1:S])
@variable(TWO_THREE, O_prod[1:O])

@variable(TWO_THREE, theta[1:N])                              #########################################   voltage angle
@variable(TWO_THREE, power_flow[1:N,1:M])                     #########################################   power flow (this variable is not necessarv but it is for an easier visualization of the code/model)

@variable(TWO_THREE, S_alpha_offer[1:S])
@variable(TWO_THREE, demand[1:D])

# DUAL KKT

@variable(TWO_THREE, lambda[1:N])                             #########################################  changed to general lambda to lambda per node
@variable(TWO_THREE, gamma)                                   #########################################  dual variable of the reference voltage angle

@variable(TWO_THREE, mu_D_up[1:D])
@variable(TWO_THREE, mu_D_down[1:D])

@variable(TWO_THREE, mu_O_up[1:O])
@variable(TWO_THREE, mu_O_down[1:O])

@variable(TWO_THREE, mu_S_up[1:S])
@variable(TWO_THREE, mu_S_down[1:S])

@variable(TWO_THREE, eta_N_up[1:N,1:M])                                            #########################################   dual variable of capacity constraint fo power flow - upper bound
@variable(TWO_THREE, eta_N_down[1:N,1:M])                                          #########################################   dual variable of capacity constraint fo power flow - lower bound


# BINARY FOR BIG M LINEAERIZATION

@variable(TWO_THREE, epsi_D_up[1:D], Bin)                                                     # 11
@variable(TWO_THREE, epsi_D_down[1:D], Bin)                                                   # 16

@variable(TWO_THREE, epsi_O_up[1:O], Bin)                                                     # 21
@variable(TWO_THREE, epsi_O_down[1:O], Bin)                                                   # 26

@variable(TWO_THREE, epsi_S_up[1:S], Bin)                                                    # 31
@variable(TWO_THREE, epsi_S_down[1:S], Bin)                                                  # 36

@variable(TWO_THREE, epsi_N_up[1:N,1:M], Bin)                                            #########################################   binary variable for the BIM M linearization of the KKTs capacity contraint
@variable(TWO_THREE, epsi_N_down[1:N,1:M], Bin)                                          #########################################   in the lower level model 

@constraint(TWO_THREE,[s=1:S], S_alpha_offer[s] >= S_cost[s])                                 # 1
@constraint(TWO_THREE,[s=1:S], S_alpha_offer[s] >= 0)                                         # 2
@constraint(TWO_THREE,[d=1:D], - D_bid_price[d] + mu_D_up[d] - mu_D_down[d] + sum(lambda[n]*(D_Location[d]==n ? 1 : 0) for n=1:N)  == 0)    # 3                              ############################### I used the sum because anyway for each O/S/D there will be 
@constraint(TWO_THREE,[s=1:S], S_alpha_offer[s] + mu_S_up[s] - mu_S_down[s] - sum(lambda[n]*(S_Location[s]==n ? 1 : 0) for n=1:N) == 0)     # 4                              ############################### just one so it will be the sum of one only
@constraint(TWO_THREE,[o=1:O],        O_cost[o] + mu_O_up[o] - mu_O_down[o] - sum(lambda[n]*(O_Location[o]==n ? 1 : 0) for n=1:N) == 0)     # 5                              ###############################
@constraint(TWO_THREE,[n=1:N], sum(BB*N_table[n,m]*(lambda[n] - lambda[m] + eta_N_up[n,m] - eta_N_down[n,m]) for m=1:M)  + (n==1 ? 1 : 0)*gamma == 0)          # 6           ################################
@constraint(TWO_THREE,[n=1:N], sum(demand[d]*(D_Location[d] == n ? 1 : 0) for d=1:D) + sum(power_flow[n,m] for m=1:M) - sum(S_prod[s]*(S_Location[s]==n ? 1 : 0) for s=1:S) - sum(O_prod[o]*(O_Location[o]==n ? 1 : 0) for o=1:O) == 0) # 6     ############

@constraint(TWO_THREE, [n=1:N,m=1:M], power_flow[n,m] == BB*N_table[n,m]*(theta[n] - theta[m]))                                 #########################################
@constraint(TWO_THREE, [n=1:N,m=1:M], - N_capacity*N_table[n,m] <= power_flow[n,m] <= N_capacity*N_table[n,m])                  #########################################   line capacity contraint
@constraint(TWO_THREE, theta[1] == 0)                                                                                           #########################################   voltage reference angle

# DEMAND - D

@constraint(TWO_THREE, [d=1:D], demand[d]<=D_quantity[d])                                     # 7
@constraint(TWO_THREE, [d=1:D], mu_D_up[d]>=0)                                                # 8
@constraint(TWO_THREE, [d=1:D], D_quantity[d] - demand[d] <= epsi_D_up[d]*Big_M)              # 9
@constraint(TWO_THREE, [d=1:D], mu_D_up[d] <= (1 - epsi_D_up[d])*Big_M)                       # 10
                                                                                              # 11 is in the variable
@constraint(TWO_THREE,[d=1:D], demand[d] >= 0)                                                # 12
@constraint(TWO_THREE,[d=1:D], mu_D_down[d] >= 0)                                             # 13
@constraint(TWO_THREE,[d=1:D], demand[d] <= epsi_D_down[d]*Big_M)                             # 14
@constraint(TWO_THREE,[d=1:D], mu_D_down[d] <= (1 - epsi_D_down[d])*Big_M)                    # 15
                                                                                              # 16 is in the variable

# PRICE MAKER - LEADER - S

@constraint(TWO_THREE, [s=1:S], S_prod[s]<=S_capacity[s])                                     # 17
@constraint(TWO_THREE,[s=1:S], mu_S_up[s]>=0)                                                 # 18
@constraint(TWO_THREE, [s=1:S], S_capacity[s] - S_prod[s] <= epsi_S_up[s]*Big_M)              # 19
@constraint(TWO_THREE,[s=1:S], mu_S_up[s] <= (1 - epsi_S_up[s])*Big_M)                        # 20
# 21 is in the variable
@constraint(TWO_THREE,[s=1:S], S_prod[s] >= 0)                                                # 22
@constraint(TWO_THREE,[s=1:S], mu_S_down[s] >= 0)                                             # 23
@constraint(TWO_THREE,[s=1:S], S_prod[s] <= epsi_S_down[s]*Big_M)                             # 24
@constraint(TWO_THREE,[s=1:S], mu_S_down[s] <= (1 - epsi_S_down[s])*Big_M)                    # 25
                                                                                              # 26 is in the variable

# PRICE TAKER - FOLLOWERS - O

@constraint(TWO_THREE, [o=1:O], O_prod[o] <= O_capacity[o])                                   # 27
@constraint(TWO_THREE, [o=1:O], mu_O_up[o] >= 0)                                              # 28
@constraint(TWO_THREE, [o=1:O], O_capacity[o] - O_prod[o] <= epsi_O_up[o]*Big_M)              # 29
@constraint(TWO_THREE, [o=1:O], mu_O_up[o] <= (1 - epsi_O_up[o])*Big_M)                       # 30
# 31 is in the variable
@constraint(TWO_THREE,[o=1:O], O_prod[o] >= 0)                                                # 32
@constraint(TWO_THREE,[o=1:O], mu_O_down[o] >= 0)                                             # 33
@constraint(TWO_THREE,[o=1:O], O_prod[o] <= epsi_O_down[o]*Big_M)                             # 34
@constraint(TWO_THREE,[o=1:O], mu_O_down[o] <= (1 - epsi_O_down[o])*Big_M)                    # 35
                                                                                              # 36 is in the variable

# NETWORK 

# a = capacity +- power_flow
# b = eta[n,m]

@constraint(TWO_THREE, [n=1:N,m=1:M], (N_capacity*N_table[n,m] - power_flow[n,m]) >= 0)                                 ################################## 
@constraint(TWO_THREE, [n=1:N,m=1:M], eta_N_up[n,m] >= 0)                                                               ################################## 
@constraint(TWO_THREE, [n=1:N,m=1:M], (N_capacity*N_table[n,m] - power_flow[n,m]) <= epsi_N_up[n,m]*Big_M)              ################################## 
@constraint(TWO_THREE, [n=1:N,m=1:M],  eta_N_up[n,m] <= (1 - epsi_N_up[n,m])*Big_M)                                     ################################## 

@constraint(TWO_THREE, [n=1:N,m=1:M], (N_capacity*N_table[n,m] + power_flow[n,m]) >= 0)                                 ################################## 
@constraint(TWO_THREE, [n=1:N,m=1:M], eta_N_down[n,m] >= 0)                                                             ################################## 
@constraint(TWO_THREE, [n=1:N,m=1:M], (N_capacity*N_table[n,m] + power_flow[n,m]) <= epsi_N_down[n,m]*Big_M)            ################################## 
@constraint(TWO_THREE, [n=1:N,m=1:M],  eta_N_down[n,m] <= (1-epsi_N_down[n,m])*Big_M)                                   ################################## 



@objective(TWO_THREE, Max, - sum(S_prod[s]*S_cost[s] for s=1:S) 
                           + sum(D_bid_price[d]*demand[d] for d=1:D)
                           - sum(O_cost[o]*O_prod[o] for o=1:O)
                           - sum(mu_D_up[d]*D_quantity[d] for d=1:D)
                           - sum(mu_O_up[o]*O_capacity[o] for o=1:O)
                           - sum(eta_N_up[n,m]*N_capacity*N_table[n,m] for n=1:N,m=1:M) 
                           - sum(eta_N_down[n,m]*-N_capacity*N_table[n,m] for n=1:N,m=1:M)
)

start_time = time()
optimize!(TWO_THREE)
end_time = time()

for s=1:S
    println("Offer Price ", GEN_S[s], @sprintf(" %.2f \$" , value(S_alpha_offer[s]))," - Production cost: ", @sprintf(" %.2f \$" , S_cost[s]))
end 

println("\n")

for s=1:S
    println("Power Production ", GEN_S[s], @sprintf(" %.2f MW" , value(S_prod[s]))," - Production cost: ", @sprintf(" %.2f \$" , S_cost[s]), " - Capacity: ", @sprintf(" %.2f \$" , S_capacity[s]), "  Located in N", value(S_Location[s]) )
end 
println("\n")
for o=1:O
    println("Power Production ", GEN_O[o], @sprintf(" %.2f MW" , value(O_prod[o]))," - Production cost: ", @sprintf(" %.2f \$" , O_cost[o]), " Located in N", value(O_Location[o]))
end 

println("\n")
for d=1:D
    println("Demand covered: ", DEMAND[d], @sprintf(" %.2f MW" , value(demand[d]))," - Bid price: ", @sprintf(" %.2f \$" , D_bid_price[d]), " Located in N", value(D_Location[d]))
end 



println("\n")
for n=1:N
println("Market clearing price at node ", NODE[n], @sprintf(": %.2f \$" , value(lambda[n])))
end

println("\n")
for n=1:N
    for m=1:M
        println("Power flow from node ", NODE[n], " to node ", NODE[m], @sprintf(": %.2f MW" , value(power_flow[n,m])))
    end
end


# Print number of variables and constraints
println("\n")
println("Number of variables: ", JuMP.num_variables(TWO_THREE))
println("Number of constraints: ", JuMP.num_constraints(TWO_THREE, count_variable_in_set_constraints=false))


# Print computational time
println("Computational time: ", end_time - start_time)